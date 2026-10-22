/// KashU App Constants
class AppConstants {
  AppConstants._();

  // Hive Box Names
  static const String assetsBox = 'assets_box';
  static const String transactionsBox = 'transactions_box';
  static const String settingsBox = 'settings_box';
  static const String priceCacheBox = 'price_cache_box';
  static const String priceHistoryBox = 'price_history_box';

  /// Every AES-encrypted box. DatabaseKeyService uses the list to tell a
  /// fresh install from data whose key went missing, and its reset deletes
  /// all of them.
  static const List<String> encryptedBoxes = [
    settingsBox,
    assetsBox,
    transactionsBox,
    priceCacheBox,
    priceHistoryBox,
  ];

  /// Unencrypted box holding only a check value of the encryption key, so a
  /// key that doesn't match the data is caught before any box is opened.
  static const String keyCheckBox = 'key_check_box';

  // Settings Keys
  static const String keyBiometricEnabled = 'biometric_enabled';
  static const String keyPinEnabled = 'pin_enabled';
  static const String keyPin = 'pin';
  static const String keyBaseCurrency = 'base_currency';
  static const String keyThemeMode = 'theme_mode';
  static const String keyOnboardingComplete = 'onboarding_complete';
  static const String keyAppLockEnabled = 'app_lock_enabled';
  static const String keySchemaVersion = 'schema_version';
  static const String keyCrashReportingEnabled = 'crash_reporting_enabled';
  static const String keyLastExportAt = 'last_export_at';
  static const String keyBackupNudgeDismissedAt = 'backup_nudge_dismissed_at';

  /// Asset ids whose delete started but has not been confirmed complete —
  /// written by PortfolioWriteService before it touches either box, cleared
  /// after both halves succeed, finished at startup if interrupted.
  static const String keyPendingAssetDeletes = 'pending_asset_deletes';

  /// True while a Clear All Data is in flight (set before the first box is
  /// cleared, removed after the last) — finished at startup if interrupted.
  static const String keyPendingClearAll = 'pending_clear_all';

  /// Journal of a backup import in flight: the previous value of every
  /// asset/transaction id it writes (null for new ids) plus the delete
  /// tombstones. Written before the first box write, removed once the import
  /// is complete; a leftover journal is rolled back at startup.
  static const String keyPendingImport = 'pending_import';

  /// The settings_box entries that survive Clear All Data: the user's
  /// preferences (base currency, theme, app lock and PIN, crash-reporting
  /// consent, onboarding done) plus the on-disk schema version. Everything
  /// else in the box describes the portfolio (rebalancing targets,
  /// pending-write markers, refresh and backup timestamps) and is wiped
  /// with it, so a NEW PREFERENCE KEY MUST BE ADDED HERE or Clear All Data
  /// will reset it.
  static const Set<String> preservedSettingsKeys = {
    keyBaseCurrency,
    keyThemeMode,
    keyOnboardingComplete,
    keyAppLockEnabled,
    keyBiometricEnabled,
    keyPinEnabled,
    keyPin,
    keyCrashReportingEnabled,
    keySchemaVersion,
  };

  /// Version of the backup/export JSON file format. Independent of the Hive
  /// on-disk schema version tracked by HiveMigrationService — bump this only
  /// when the structure of exported JSON changes.
  static const int backupFormatVersion = 2;

  /// The public privacy policy (served from web/privacy.html) and the support
  /// address it, Settings and the Play listing all point to.
  static const String privacyPolicyUrl =
      'https://kash-u.vercel.app/privacy.html';
  static const String contactEmail = 'onelunchdev@gmail.com';

  // Animation Durations
  static const Duration animationFast = Duration(milliseconds: 200);
  static const Duration animationNormal = Duration(milliseconds: 300);
  static const Duration animationSlow = Duration(milliseconds: 500);

  // Supported Currencies
  static const Map<String, String> currencies = {
    'INR': '₹',
    'USD': '\$',
    'EUR': '€',
    'GBP': '£',
    'JPY': '¥',
    'AED': 'د.إ',
    'SGD': 'S\$',
    'AUD': 'A\$',
    'CAD': 'C\$',
    'CHF': 'CHF',
  };

  // Default exchange rates to INR (for manual mode, user can update)
  static const Map<String, double> defaultExchangeRates = {
    'INR': 1.0,
    'USD': 83.0,
    'EUR': 90.0,
    'GBP': 105.0,
    'JPY': 0.55,
    'AED': 22.6,
    'SGD': 62.0,
    'AUD': 54.0,
    'CAD': 61.0,
    'CHF': 95.0,
  };

  // Platforms/Brokers
  static const List<String> popularPlatforms = [
    'Zerodha',
    'Groww',
    'Upstox',
    'Angel One',
    'ICICI Direct',
    'HDFC Securities',
    'Kotak Securities',
    'Paytm Money',
    'Coin by Zerodha',
    'Kuvera',
    'INDmoney',
    'ET Money',
    'WazirX',
    'CoinDCX',
    'Binance',
    'Bank FD',
    'Post Office',
    'Physical',
    'Other',
  ];
}
