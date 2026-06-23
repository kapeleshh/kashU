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

Future<void> _bootstrap() async {
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

  // Open Hive boxes with encryption.
  // If any box fails (corrupted file, storage full) show a recovery screen
  // instead of crashing with an unintelligible HiveError.
  try {
    await Hive.openBox<Asset>(AppConstants.assetsBox,
        encryptionCipher: cipher);
    await Hive.openBox<Transaction>(AppConstants.transactionsBox,
        encryptionCipher: cipher);
    await Hive.openBox(AppConstants.settingsBox, encryptionCipher: cipher);
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
      child: KashUApp(
        showOnboarding: !onboardingComplete,
        showLock: appLockEnabled,
      ),
    ),
  );
}

void main() async {
  if (AppConfig.isSentryEnabled) {
    await SentryFlutter.init(
      (options) {
        options.dsn = AppConfig.sentryDsn;
        options.environment = AppConfig.environment;
        options.tracesSampleRate = 0.2; // 20% of transactions for performance
        options.attachScreenshot = true;
      },
      appRunner: _bootstrap,
    );
  } else {
    await _bootstrap();
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

class KashUApp extends StatelessWidget {
  final bool showOnboarding;
  final bool showLock;

  const KashUApp({
    super.key,
    required this.showOnboarding,
    required this.showLock,
  });

  @override
  Widget build(BuildContext context) {
    // Priority: onboarding > lock screen > dashboard
    Widget home;
    if (showOnboarding) {
      home = const OnboardingScreen();
    } else if (showLock) {
      home = const LockScreen();
    } else {
      home = const DashboardScreen();
    }

    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: home,
    );
  }
}
