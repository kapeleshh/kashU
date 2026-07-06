import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'core/config/app_config.dart';
import 'core/config/crash_reporting_consent.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_strings.dart';
import 'core/constants/app_constants.dart';
import 'data/migration/hive_migration_service.dart';
import 'data/models/asset_type.dart';
import 'data/models/transaction_type.dart';
import 'data/models/asset.dart';
import 'data/models/transaction.dart';
import 'features/auth/lock_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'shared/providers/portfolio_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Hive encryption setup
// ─────────────────────────────────────────────────────────────────────────────

/// Secure storage key for the Hive AES encryption key.
const _kHiveEncryptionKey = 'kashu_hive_aes_key';

/// Retrieve the persisted Hive encryption key, or generate + store a new one.
Future<HiveAesCipher> _loadOrCreateCipher() async {
  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final existing = await storage.read(key: _kHiveEncryptionKey);
  List<int> keyBytes;

  if (existing != null) {
    keyBytes = base64Decode(existing);
  } else {
    final rng = Random.secure();
    keyBytes = List<int>.generate(32, (_) => rng.nextInt(256));
    await storage.write(
      key: _kHiveEncryptionKey,
      value: base64Encode(keyBytes),
    );
  }

  return HiveAesCipher(keyBytes);
}

// ─────────────────────────────────────────────────────────────────────────────
// Global error handler
// ─────────────────────────────────────────────────────────────────────────────

void _setupErrorHandlers() {
  // Catch unhandled Flutter framework errors (rendering, layout, etc.)
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    if (AppConfig.isSentryEnabled) {
      Sentry.captureException(details.exception, stackTrace: details.stack);
    }
    debugPrint('[KashU] FlutterError: ${details.exception}');
  };

  // Catch unhandled async/isolate errors outside the Flutter framework
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[KashU] Unhandled error: $error\n$stack');
    if (AppConfig.isSentryEnabled) {
      Sentry.captureException(error, stackTrace: stack);
    }
    return false; // false = allow default crash behaviour on fatal errors
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// App entry point
// ─────────────────────────────────────────────────────────────────────────────

/// Phase 1 of startup: everything needed to read user settings — and nothing
/// more. Runs before Sentry so the crash-reporting consent flag can be read
/// from the (encrypted) settings box before any SDK is initialised.
///
/// Returns the cipher for [_bootstrap] to open the remaining boxes with, or
/// null if the settings box could not be opened (the error screen is already
/// shown in that case).
Future<HiveAesCipher?> _preBootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set up global error handlers before anything else
  _setupErrorHandlers();

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // Initialize Hive
  await Hive.initFlutter();

  // Register Hive adapters
  Hive.registerAdapter(AssetTypeAdapter());
  Hive.registerAdapter(TransactionTypeAdapter());
  Hive.registerAdapter(AssetAdapter());
  Hive.registerAdapter(TransactionAdapter());

  // Load (or create) the AES cipher backed by flutter_secure_storage.
  // All boxes are encrypted with the same key — the key itself never
  // touches disk unprotected (it lives in the platform keychain/keystore).
  final cipher = await _loadOrCreateCipher();

  try {
    await Hive.openBox(AppConstants.settingsBox, encryptionCipher: cipher);
  } catch (e, stack) {
    debugPrint('[KashU] Failed to open settings box: $e\n$stack');
    runApp(_DatabaseErrorApp(error: e.toString()));
    return null;
  }

  return cipher;
}

/// Phase 2 of startup: open the data boxes, migrate, and run the app.
Future<void> _bootstrap(HiveAesCipher cipher) async {
  // Open the remaining Hive boxes with encryption.
  // If any box fails (corrupted file, storage full) show a recovery screen
  // instead of crashing with an unintelligible HiveError.
  try {
    await Hive.openBox<Asset>(AppConstants.assetsBox,
        encryptionCipher: cipher);
    await Hive.openBox<Transaction>(AppConstants.transactionsBox,
        encryptionCipher: cipher);
    await Hive.openBox(AppConstants.priceCacheBox, encryptionCipher: cipher);
  } catch (e, stack) {
    debugPrint('[KashU] Failed to open Hive boxes: $e\n$stack');
    if (AppConfig.isSentryEnabled) {
      await Sentry.captureException(e, stackTrace: stack);
    }
    runApp(_DatabaseErrorApp(error: e.toString()));
    return;
  }

  // Run any pending schema migrations
  await HiveMigrationService.runMigrations();

  // Read startup flags from settings (after boxes are open)
  final settings = Hive.box(AppConstants.settingsBox);
  final onboardingComplete =
      settings.get(AppConstants.keyOnboardingComplete, defaultValue: false) as bool;
  final appLockEnabled =
      settings.get(AppConstants.keyAppLockEnabled, defaultValue: false) as bool;

  runApp(
    ProviderScope(
      overrides: [
        // Start locked when app lock is enabled. Never lock over onboarding.
        appLockedProvider
            .overrideWith((ref) => appLockEnabled && onboardingComplete),
      ],
      child: KashUApp(showOnboarding: !onboardingComplete),
    ),
  );
}

bool _readCrashReportingConsent() {
  final settings = Hive.box(AppConstants.settingsBox);
  return crashReportingConsentGiven(
      settings.get(AppConstants.keyCrashReportingEnabled));
}

void main() async {
  final cipher = await _preBootstrap();
  if (cipher == null) return; // settings box unopenable — error screen shown

  // Sentry runs only when a DSN was baked in at build time AND the user
  // opted in via Settings. Consent is read from the encrypted settings box,
  // which is why Sentry initialises after _preBootstrap.
  if (AppConfig.isSentryEnabled && _readCrashReportingConsent()) {
    await SentryFlutter.init(
      (options) {
        options.dsn = AppConfig.sentryDsn;
        options.environment = AppConfig.environment;
        options.tracesSampleRate = 0.2; // 20% of transactions for performance
        // Privacy hardening: screenshots would leak portfolio balances, and
        // http breadcrumbs carry request URLs whose query strings contain
        // asset symbols — i.e. the user's holdings.
        options.attachScreenshot = false;
        options.sendDefaultPii = false;
        options.beforeBreadcrumb = (breadcrumb, hint) {
          if (breadcrumb?.type == 'http') return null;
          return breadcrumb;
        };
        // Honour the toggle being switched off mid-session: consent is
        // re-checked per event, so nothing is sent after the flip even
        // though the SDK stays initialised until restart.
        options.beforeSend = (event, hint) {
          return _readCrashReportingConsent() ? event : null;
        };
      },
      appRunner: () => _bootstrap(cipher),
    );
  } else {
    await _bootstrap(cipher);
  }
}

/// Shown when Hive boxes cannot be opened (corrupted data, storage full, etc.).
/// Gives the user an actionable message rather than a blank crash.
class _DatabaseErrorApp extends StatelessWidget {
  final String error;
  const _DatabaseErrorApp({required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0D0D1A),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline,
                    color: Color(0xFFEF5350), size: 64),
                const SizedBox(height: 24),
                const Text(
                  'Unable to open database',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'KashU could not open its local database. This can happen '
                  'if storage is full or the database file is corrupted.\n\n'
                  'Try freeing up storage space and restarting the app. '
                  'If the problem persists, reinstalling the app will clear '
                  'the database (your data will be lost unless you have a backup).',
                  style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Text(
                  error,
                  style: const TextStyle(
                      color: Color(0xFF666666), fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class KashUApp extends ConsumerStatefulWidget {
  final bool showOnboarding;

  /// How long the app may stay in the background before it re-locks.
  /// Short pauses (notification shade, quick app switch) don't re-lock.
  final Duration relockGracePeriod;

  const KashUApp({
    super.key,
    required this.showOnboarding,
    this.relockGracePeriod = const Duration(seconds: 30),
  });

  @override
  ConsumerState<KashUApp> createState() => _KashUAppState();
}

class _KashUAppState extends ConsumerState<KashUApp>
    with WidgetsBindingObserver {
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only paused/resumed matter. `inactive` and `hidden` are deliberately
    // ignored — biometric sheets, permission dialogs, and the app switcher
    // all fire `inactive`, and re-locking on those would cause biometric
    // re-prompt storms.
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      _maybeRelock();
    }
  }

  void _maybeRelock() {
    final pausedAt = _pausedAt;
    _pausedAt = null;
    if (pausedAt == null) return;

    // Read the flags live so toggling app lock off works without a restart,
    // and onboarding is never covered by the lock.
    final settings = Hive.box(AppConstants.settingsBox);
    final lockEnabled = settings.get(AppConstants.keyAppLockEnabled,
        defaultValue: false) as bool;
    final onboardingComplete = settings.get(AppConstants.keyOnboardingComplete,
        defaultValue: false) as bool;
    if (!lockEnabled || !onboardingComplete) return;

    if (DateTime.now().difference(pausedAt) >= widget.relockGracePeriod) {
      ref.read(appLockedProvider.notifier).state = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(appLockedProvider);
    final home = widget.showOnboarding
        ? const OnboardingScreen()
        : const DashboardScreen();

    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      // C·Soft theme — all screens are theme-aware, so follow the device.
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: home,
      // The lock is an overlay above the whole app rather than a route:
      // navigation state survives lock/unlock, and there is no way to
      // navigate around the lock.
      builder: (context, child) => Stack(
        children: [
          if (child != null) child,
          if (locked) const LockScreen(),
        ],
      ),
    );
  }
}
