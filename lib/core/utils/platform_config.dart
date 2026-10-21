import 'package:flutter/foundation.dart' show kIsWeb;

/// Centralises all platform-specific URL building logic.
///
/// All API services previously duplicated `kIsWeb` proxy-routing logic.
/// This class is the single place that decides how to build a URL, so:
/// - Removing the proxy only requires changing one file.
/// - Services have no direct dependency on `kIsWeb`.
/// - Testing services is cleaner (no Flutter platform detection needed).
abstract final class PlatformConfig {
  /// Same-origin path of the CORS proxy (web only) — served by
  /// `api/proxy.py` on Vercel and by `proxy_server.py` in local dev.
  static const String _proxyPath = '/api/proxy';

  /// Whether the app is running in a browser.
  static bool get isWeb => kIsWeb;

  /// Build the [Uri] to use for [directUrl].
  ///
  /// On mobile/desktop: returns [directUrl] as-is.
  /// On web:          routes through the same-origin CORS proxy.
  static Uri buildUrl(String directUrl) {
    if (isWeb) {
      // Uri.base is the page URL on web, so this resolves against the
      // current origin and works unchanged on localhost, Vercel
      // previews, and production.
      return Uri.base
          .resolve('$_proxyPath?url=${Uri.encodeComponent(directUrl)}');
    }
    return Uri.parse(directUrl);
  }
}
