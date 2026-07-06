/// KashU App Constants
class AppConstants {
  AppConstants._();

  // Hive Box Names
  static const String assetsBox = 'assets_box';
  static const String transactionsBox = 'transactions_box';
  static const String settingsBox = 'settings_box';
  static const String priceCacheBox = 'price_cache_box';

  // Settings Keys
  static const String keyBiometricEnabled = 'biometric_enabled';
  static const String keyPinEnabled = 'pin_enabled';
  static const String keyPin = 'pin';
  static const String keyBaseCurrency = 'base_currency';
  static const String keyThemeMode = 'theme_mode';
  static const String keyOnboardingComplete = 'onboarding_complete';
  static const String keyAppLockEnabled = 'app_lock_enabled';
  static const String keySchemaVersion = 'schema_version';
  static const String keyLastExportAt = 'last_export_at';
  static const String keyBackupNudgeDismissedAt = 'backup_nudge_dismissed_at';

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
