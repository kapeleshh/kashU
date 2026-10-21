import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:kashu/core/constants/app_constants.dart';
import 'package:kashu/features/settings/settings_screen.dart';
import 'package:kashu/services/auth_service.dart';
import 'package:kashu/shared/providers/portfolio_provider.dart';

/// Deterministic auth: never prompts, always returns [result], and counts
/// how often it was asked.
class _StubAuthService implements AuthService {
  final AuthResult result;
  int calls = 0;
  _StubAuthService(this.result);

  @override
  Future<AuthResult> authenticate(
      {String reason = 'Authenticate to open KashU'}) async {
    calls++;
    return result;
  }

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> isEnrolled() async => true;
}

void main() {
  late Box settings;

  setUp(() async {
    // In-memory box: writes complete without real file I/O, so the toggle's
    // awaited put() resolves inside the widget test's fake-async zone.
    settings =
        await Hive.openBox(AppConstants.settingsBox, bytes: Uint8List(0));
  });

  tearDown(() async {
    await Hive.close();
  });

  bool? savedFlag() => settings.get(AppConstants.keyAppLockEnabled) as bool?;

  Future<_StubAuthService> pumpSettings(
    WidgetTester tester,
    AuthResult result, {
    bool lockEnabled = false,
  }) async {
    await settings.put(AppConstants.keyAppLockEnabled, lockEnabled);
    final auth = _StubAuthService(result);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authServiceProvider.overrideWithValue(auth)],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();
    return auth;
  }

  Finder lockSwitch() => find.widgetWithText(
      SwitchListTile, 'Require Authentication');

  bool switchValue(WidgetTester tester) =>
      tester.widget<SwitchListTile>(lockSwitch()).value;

  Future<void> tapLockSwitch(WidgetTester tester) async {
    await tester.tap(lockSwitch());
    await tester.pump();
    await tester.pump();
  }

  group('turning app lock on', () {
    for (final result in AuthResult.values
        .where((r) => r != AuthResult.success)) {
      testWidgets('is refused when authentication returns ${result.name}',
          (tester) async {
        final auth = await pumpSettings(tester, result);

        await tapLockSwitch(tester);

        expect(auth.calls, 1);
        expect(savedFlag(), isFalse);
        expect(switchValue(tester), isFalse);
        expect(find.byType(SnackBar), findsOneWidget);
      });
    }

    testWidgets('is saved only after a successful authentication',
        (tester) async {
      final auth = await pumpSettings(tester, AuthResult.success);

      await tapLockSwitch(tester);

      expect(auth.calls, 1);
      expect(savedFlag(), isTrue);
      expect(switchValue(tester), isTrue);
    });
  });

  group('turning app lock off', () {
    testWidgets('requires authentication', (tester) async {
      final auth = await pumpSettings(tester, AuthResult.failure,
          lockEnabled: true);

      await tapLockSwitch(tester);

      expect(auth.calls, 1);
      expect(savedFlag(), isTrue);
      expect(switchValue(tester), isTrue);
    });

    testWidgets('is refused while biometrics are locked out', (tester) async {
      await pumpSettings(tester, AuthResult.lockedOut, lockEnabled: true);

      await tapLockSwitch(tester);

      expect(savedFlag(), isTrue);
    });

    testWidgets('succeeds after a successful authentication', (tester) async {
      await pumpSettings(tester, AuthResult.success, lockEnabled: true);

      await tapLockSwitch(tester);

      expect(savedFlag(), isFalse);
      expect(switchValue(tester), isFalse);
    });

    testWidgets(
        'is allowed when the device can no longer authenticate at all — '
        'the lock is inert and must not stay stuck on', (tester) async {
      await pumpSettings(tester, AuthResult.notAvailable, lockEnabled: true);

      await tapLockSwitch(tester);

      expect(savedFlag(), isFalse);
    });
  });
}
