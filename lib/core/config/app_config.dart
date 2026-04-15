/// Runtime configuration sourced from --dart-define at build time.
///
/// To enable Sentry crash reporting, build with:
///   flutter build apk --dart-define=SENTRY_DSN=https://xxx@sentry.io/yyy
///
/// Without a DSN the app runs normally — Sentry is simply a no-op.
abstract final class AppConfig {
  /// Sentry Data Source Name. Empty string = crash reporting disabled.
  static const String sentryDsn = String.fromEnvironment('SENTRY_DSN');

  /// Whether Sentry is configured and should be initialised.
  static bool get isSentryEnabled => sentryDsn.isNotEmpty;

  /// App environment label sent with every Sentry event.
  static const String environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'production',
  );
}
