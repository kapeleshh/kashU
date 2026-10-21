import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mocktail/mocktail.dart';

import 'package:kashu/services/auth_service.dart';

class MockLocalAuthentication extends Mock implements LocalAuthentication {}

void main() {
  late MockLocalAuthentication localAuth;
  late AuthService service;

  setUpAll(() {
    registerFallbackValue(const AuthenticationOptions());
  });

  setUp(() {
    localAuth = MockLocalAuthentication();
    service = AuthService(auth: localAuth);
    when(() => localAuth.isDeviceSupported()).thenAnswer((_) async => true);
    when(() => localAuth.canCheckBiometrics).thenAnswer((_) async => true);
  });

  void stubAuthenticate(Future<bool> Function() answer) {
    when(() => localAuth.authenticate(
          localizedReason: any(named: 'localizedReason'),
          options: any(named: 'options'),
        )).thenAnswer((_) => answer());
  }

  void stubPlatformError(String code) {
    stubAuthenticate(() async => throw PlatformException(code: code));
  }

  test('success when the platform authenticates the user', () async {
    stubAuthenticate(() async => true);
    expect(await service.authenticate(), AuthResult.success);
  });

  test('failure when the prompt ends without authenticating', () async {
    // Android reports a dismissed BiometricPrompt as plain `false`.
    stubAuthenticate(() async => false);
    expect(await service.authenticate(), AuthResult.failure);
  });

  test('notAvailable without prompting when the device has no support',
      () async {
    when(() => localAuth.isDeviceSupported()).thenAnswer((_) async => false);

    expect(await service.authenticate(), AuthResult.notAvailable);
    verifyNever(() => localAuth.authenticate(
          localizedReason: any(named: 'localizedReason'),
          options: any(named: 'options'),
        ));
  });

  test('allows the device PIN/pattern fallback', () async {
    stubAuthenticate(() async => true);
    await service.authenticate(reason: 'Confirm');

    final options = verify(() => localAuth.authenticate(
          localizedReason: 'Confirm',
          options: captureAny(named: 'options'),
        )).captured.single as AuthenticationOptions;
    expect(options.biometricOnly, isFalse);
  });

  group('platform errors are not reported as a user failure', () {
    // The Android launch bug: with a plain FlutterActivity every attempt
    // threw `no_fragment_activity`, which used to map to `failure` — so the
    // lock screen looped on "try again" forever.
    test('no_fragment_activity is a platform error', () async {
      stubPlatformError('no_fragment_activity');
      expect(await service.authenticate(), AuthResult.error);
    });

    test('an unknown code is a platform error', () async {
      stubPlatformError('SomethingNew');
      expect(await service.authenticate(), AuthResult.error);
    });

    test('a non-platform exception is a platform error', () async {
      stubAuthenticate(() async => throw Exception('channel died'));
      expect(await service.authenticate(), AuthResult.error);
    });

    test('LockedOut and PermanentlyLockedOut are reported as lock-outs',
        () async {
      stubPlatformError('LockedOut');
      expect(await service.authenticate(), AuthResult.lockedOut);

      stubPlatformError('PermanentlyLockedOut');
      expect(await service.authenticate(), AuthResult.permanentlyLockedOut);
    });

    test('NotAvailable keeps its notAvailable meaning', () async {
      stubPlatformError('NotAvailable');
      expect(await service.authenticate(), AuthResult.notAvailable);
    });

    test('NotEnrolled and PasscodeNotSet mean nothing is enrolled', () async {
      stubPlatformError('NotEnrolled');
      expect(await service.authenticate(), AuthResult.notEnrolled);

      stubPlatformError('PasscodeNotSet');
      expect(await service.authenticate(), AuthResult.notEnrolled);
    });

    test('a user cancel or an already-open prompt is a cancel', () async {
      for (final code in ['UserCancelled', 'UserFallback', 'auth_in_progress']) {
        stubPlatformError(code);
        expect(await service.authenticate(), AuthResult.cancelled,
            reason: code);
      }
    });
  });

  test('deviceCannotAuthenticate covers only states with no usable prompt',
      () {
    final cannot = AuthResult.values
        .where((r) => r.deviceCannotAuthenticate)
        .toSet();
    expect(cannot, {
      AuthResult.notAvailable,
      AuthResult.notEnrolled,
      AuthResult.error,
    });
  });
}
