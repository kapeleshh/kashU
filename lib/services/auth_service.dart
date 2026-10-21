import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';

/// Result of an authentication attempt.
enum AuthResult {
  success,

  /// The prompt ran but the user did not authenticate (dismissed it, or the
  /// check failed). Android reports a dismissed prompt this way too.
  failure,
  notAvailable,
  notEnrolled,
  cancelled,

  /// Too many failed attempts — biometrics are disabled for a short while
  /// (about 30 seconds on Android).
  lockedOut,

  /// Biometrics are disabled until the device is unlocked with its PIN,
  /// pattern or password.
  permanentlyLockedOut,

  /// Authentication could not run at all because of a platform or
  /// configuration problem (e.g. `no_fragment_activity`) — nothing the user
  /// did, and retrying will usually fail the same way.
  error,
}

extension AuthResultX on AuthResult {
  /// True when the device cannot authenticate the user at all, so an app
  /// lock could not protect anything — the lock screen lets the user in
  /// (or offers to) in these states.
  bool get deviceCannotAuthenticate =>
      this == AuthResult.notAvailable ||
      this == AuthResult.notEnrolled ||
      this == AuthResult.error;
}

/// Wraps `local_auth` for biometric / device-credential authentication.
///
/// Uses the device's built-in mechanism (fingerprint, Face ID, device PIN, etc.)
/// — the user does not need to set a separate in-app PIN.
class AuthService {
  final LocalAuthentication _auth;

  AuthService({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  /// Returns true if the device supports biometric or device-credential auth.
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Returns true if the device has enrolled biometrics or a PIN/pattern.
  Future<bool> isEnrolled() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck || isSupported;
    } catch (_) {
      return false;
    }
  }

  /// Prompt the user for authentication.
  ///
  /// [reason] — the message shown in the OS authentication dialog.
  /// Returns an [AuthResult] describing the outcome.
  Future<AuthResult> authenticate({
    String reason = 'Authenticate to open KashU',
  }) async {
    try {
      final available = await isAvailable();
      if (!available) return AuthResult.notAvailable;

      final enrolled = await isEnrolled();
      if (!enrolled) return AuthResult.notEnrolled;

      final authenticated = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false, // allow device PIN/pattern as fallback
          stickyAuth: true,     // don't cancel if user switches apps briefly
        ),
      );

      return authenticated ? AuthResult.success : AuthResult.failure;
    } on PlatformException catch (e) {
      debugPrint('[KashU] Authentication error: ${e.code}');
      return resultForPlatformCode(e.code);
    } on Exception catch (e) {
      debugPrint('[KashU] Authentication error: $e');
      return AuthResult.error;
    }
  }

  /// Map a `local_auth` [PlatformException] code to an [AuthResult].
  ///
  /// The codes come from `local_auth/error_codes.dart` plus the
  /// platform-specific ones the Android and Darwin implementations throw.
  /// Anything unrecognised is a platform [AuthResult.error], never a user
  /// [AuthResult.failure] — "tap to try again" cannot fix a broken setup.
  @visibleForTesting
  static AuthResult resultForPlatformCode(String code) {
    switch (code) {
      case auth_error.notAvailable:
        return AuthResult.notAvailable;
      case auth_error.notEnrolled:
      case auth_error.passcodeNotSet:
        return AuthResult.notEnrolled;
      case auth_error.lockedOut:
        return AuthResult.lockedOut;
      case auth_error.permanentlyLockedOut:
        return AuthResult.permanentlyLockedOut;
      case 'UserCancelled': // iOS/macOS: the sheet was dismissed
      case 'UserFallback':
      case 'auth_in_progress': // a prompt is already on screen
        return AuthResult.cancelled;
      default: // no_fragment_activity, no_activity, BiometricNotAvailable…
        return AuthResult.error;
    }
  }
}
