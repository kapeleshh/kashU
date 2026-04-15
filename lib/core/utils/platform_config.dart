import 'package:flutter/foundation.dart' show kIsWeb;

/// Centralises all platform-specific URL building logic.
///
/// All API services previously duplicated `kIsWeb` proxy-routing logic.
/// This class is the single place that decides how to build a URL, so:
/// - Removing the proxy only requires changing one file.
/// - Services have no direct dependency on `kIsWeb`.
/// - Testing services is cleaner (no Flutter platform detection needed).
abstract final class PlatformConfig {
  /// Base URL for the local CORS proxy (web only).
  static const String _proxyBase = 'http://localhost:8080/proxy?url=';

  /// Whether the app is running in a browser.
  static bool get isWeb => kIsWeb;

  /// Build the [Uri] to use for [directUrl].
  ///
  /// On mobile/desktop: returns [directUrl] as-is.
  /// On web:          routes through the local CORS proxy.
  static Uri buildUrl(String directUrl) {
    if (isWeb) {
      return Uri.parse('$_proxyBase${Uri.encodeComponent(directUrl)}');
    }
    return Uri.parse(directUrl);
  }
}
