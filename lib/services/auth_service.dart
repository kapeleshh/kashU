import 'package:local_auth/local_auth.dart';

/// Result of an authentication attempt.
enum AuthResult {
  success,
  failure,
  notAvailable,
  notEnrolled,
  cancelled,
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
    } on Exception {
      return AuthResult.failure;
    }
  }
}
