import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'core/config/app_config.dart';
import 'core/config/crash_reporting_consent.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/font_licenses.dart';
import 'core/constants/app_strings.dart';
import 'core/constants/app_constants.dart';
import 'data/migration/hive_migration_service.dart';
import 'data/repositories/portfolio_write_service.dart';
import 'data/security/database_key_service.dart';
import 'data/models/asset_type.dart';
import 'data/models/transaction_type.dart';
import 'data/models/asset.dart';
import 'data/models/transaction.dart';
import 'features/auth/lock_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/startup/database_error_app.dart';
import 'shared/providers/portfolio_provider.dart';
import 'shared/providers/settings_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Database recovery
// ─────────────────────────────────────────────────────────────────────────────

/// Replace the app with the recovery screen. Startup can be re-run from it
/// ("Try again"), or the local database and key reset first.
void _showDatabaseError(DatabaseErrorKind kind, Object? error) {
  runApp(DatabaseErrorApp(
    kind: kind,
    detail: error?.toString(),
    onRetry: () => _startApp(),
    onReset: () async {
      await DatabaseKeyService().reset();
      // A clean slate opens like a fresh install: onboarding, then the
      // user imports their backup file from Settings.
      await _startApp();
    },
  ));
}

void _registerAdapters() {
  // Guarded: startup re-runs in-process after "Try again" / a reset.
  if (Hive.isAdapterRegistered(AssetTypeAdapter().typeId)) return;
  Hive.registerAdapter(AssetTypeAdapter());
  Hive.registerAdapter(TransactionTypeAdapter());
  Hive.registerAdapter(AssetAdapter());
  Hive.registerAdapter(TransactionAdapter());
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
  _registerAdapters();

  // Load (or create) the AES cipher backed by flutter_secure_storage.
  // All boxes are encrypted with the same key — the key itself never
  // touches disk unprotected (it lives in the platform keychain/keystore).
  // A key that can't be read, has gone missing while data exists (a phone
  // backup restored without the keystore key), or doesn't match the data
  // stops here: opening the boxes with a wrong key would wipe them.
  final DatabaseKeyResult keyResult;
  try {
    keyResult = await DatabaseKeyService().loadOrCreate();
  } catch (e, stack) {
    debugPrint('[KashU] Loading the database key failed: $e\n$stack');
    _showDatabaseError(DatabaseErrorKind.keyUnavailable, e);
    return null;
  }
  final cipher = keyResult.cipher;
  if (cipher == null) {
    debugPrint('[KashU] Database key ${keyResult.problem?.name}: '
        '${keyResult.error}');
    _showDatabaseError(
        DatabaseErrorKind.keyUnavailable, 'key ${keyResult.problem?.name}');
    return null;
  }

  try {
    await Hive.openBox(AppConstants.settingsBox, encryptionCipher: cipher);
  } catch (e, stack) {
    debugPrint('[KashU] Failed to open settings box: $e\n$stack');
    _showDatabaseError(DatabaseErrorKind.openFailed, e);
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
    await Hive.openBox(AppConstants.priceHistoryBox, encryptionCipher: cipher);
  } catch (e, stack) {
    debugPrint('[KashU] Failed to open Hive boxes: $e\n$stack');
    if (AppConfig.isSentryEnabled) {
      await Sentry.captureException(e, stackTrace: stack);
    }
    _showDatabaseError(DatabaseErrorKind.openFailed, e);
    return;
  }

  // Run any pending schema migrations. The service retries failed steps by
  // itself, but if the machinery throws (e.g. disk full while persisting
  // progress) show the recovery screen — under the Sentry appRunner an
  // uncaught throw here would otherwise leave a permanently blank app.
  try {
    await HiveMigrationService.runMigrations();
  } catch (e, stack) {
    debugPrint('[KashU] Migration run failed: $e\n$stack');
    if (AppConfig.isSentryEnabled) {
      await Sentry.captureException(e, stackTrace: stack);
    }
    _showDatabaseError(DatabaseErrorKind.openFailed, e);
    return;
  }

  // Finish deletes / clear-alls that were interrupted mid-write (marked in
  // the settings box by PortfolioWriteService). Best-effort: it retries on
  // the next launch, so a failure here must never block startup.
  try {
    await PortfolioWriteService().completeInterruptedWrites();
  } catch (e, stack) {
    debugPrint('[KashU] Interrupted-write cleanup failed: $e\n$stack');
    if (AppConfig.isSentryEnabled) {
      await Sentry.captureException(e, stackTrace: stack);
    }
  }

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

/// Set once Sentry is initialised, so an in-process restart from the
/// recovery screen doesn't initialise it a second time.
bool _sentryStarted = false;

void main() {
  // Once per process: _startApp re-runs after "Try again" on the recovery
  // screen, and the licence registry does not de-duplicate.
  registerFontLicenses();
  _startApp();
}

Future<void> _startApp() async {
  final cipher = await _preBootstrap();
  if (cipher == null) return; // key or settings box unusable — error shown

  if (_sentryStarted) {
    await _bootstrap(cipher);
    return;
  }

  // Sentry runs only when a DSN was baked in at build time AND the user
  // opted in via Settings. Consent is read from the encrypted settings box,
  // which is why Sentry initialises after _preBootstrap.
  if (AppConfig.isSentryEnabled && _readCrashReportingConsent()) {
    _sentryStarted = true;
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
      // C·Soft theme — all screens are theme-aware. Settings › Appearance
      // picks System (follow the device, the default), Light or Dark; the
      // lock overlay below sits inside this theme too.
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ref.watch(themeModeProvider),
      home: home,
      // The lock is an overlay above the whole app rather than a route:
      // navigation state survives lock/unlock, and there is no way to
      // navigate around the lock.
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        // Screens without an AppBar (home, onboarding, lock) take their
        // status-bar icon colour from here, so it follows the theme too —
        // otherwise Light would keep the white icons main() starts with.
        value: _statusBarStyle(Theme.of(context).brightness),
        child: Stack(
          children: [
            if (child != null) child,
            // The lock gets its own ScaffoldMessenger: the app's root
            // messenger presents snackbars on every Scaffold it manages, so
            // without this a snackbar completing after a re-lock (e.g. a
            // price refresh result naming failed symbols — the user's
            // holdings) would paint on top of the lock screen.
            if (locked) const ScaffoldMessenger(child: LockScreen()),
          ],
        ),
      ),
    );
  }

  /// Status bar only: the navigation-bar fields stay null, so the system
  /// keeps managing that bar exactly as before.
  static SystemUiOverlayStyle _statusBarStyle(Brightness theme) {
    final dark = theme == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: theme, // iOS: the background the icons sit on
    );
  }
}
