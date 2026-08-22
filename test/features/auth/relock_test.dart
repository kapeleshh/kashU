import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:kashu/core/constants/app_constants.dart';
import 'package:kashu/data/models/asset.dart';
import 'package:kashu/data/models/asset_type.dart';
import 'package:kashu/data/models/transaction.dart';
import 'package:kashu/data/models/transaction_type.dart';
import 'package:kashu/features/auth/lock_screen.dart';
import 'package:kashu/features/dashboard/dashboard_screen.dart';
import 'package:kashu/main.dart';
import 'package:kashu/services/auth_service.dart';
import 'package:kashu/services/currency_converter_service.dart';
import 'package:kashu/shared/providers/portfolio_provider.dart';

/// Deterministic auth: never prompts, always returns [result].
class _StubAuthService implements AuthService {
  final AuthResult result;
  _StubAuthService(this.result);

  @override
  Future<AuthResult> authenticate(
          {String reason = 'Authenticate to open KashU'}) async =>
      result;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> isEnrolled() async => true;
}

/// Pump a handful of bounded frames. `pumpAndSettle` can't be used here —
/// the dashboard's CoinMascot runs a repeating animation, so the tree never
/// settles.
Future<void> pumpFrames(WidgetTester tester, [int frames = 5]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kashu_relock_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(AssetTypeAdapter().typeId)) {
      Hive.registerAdapter(AssetTypeAdapter());
      Hive.registerAdapter(TransactionTypeAdapter());
      Hive.registerAdapter(AssetAdapter());
      Hive.registerAdapter(TransactionAdapter());
    }
    await Hive.openBox<Asset>(AppConstants.assetsBox);
    await Hive.openBox<Transaction>(AppConstants.transactionsBox);
    await Hive.openBox(AppConstants.settingsBox);
    await Hive.openBox(AppConstants.priceCacheBox);

    await Hive.box(AppConstants.settingsBox).putAll({
      AppConstants.keyAppLockEnabled: true,
      AppConstants.keyOnboardingComplete: true,
    });
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    AuthResult authResult = AuthResult.cancelled,
    bool startLocked = false,
    Duration grace = Duration.zero,
  }) async {
    tester.view.physicalSize = const Size(1440, 3040);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(_StubAuthService(authResult)),
          appLockedProvider.overrideWith((ref) => startLocked),
          // The dashboard's IndexedStack builds all tab screens, which now
          // watch exchange rates — stub them so no real network/retry timer
          // leaks into this widget test.
          exchangeRatesProvider.overrideWith(
              (ref) async => ExchangeRateResult.failure('test')),
        ],
        child: KashUApp(
          showOnboarding: false,
          relockGracePeriod: grace,
        ),
      ),
    );
    await pumpFrames(tester);
  }

  Future<void> backgroundAndResume(WidgetTester tester) async {
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  }

  testWidgets('re-locks after backgrounding past the grace period',
      (tester) async {
    await pumpApp(tester); // cancelled auth → lock stays once shown
    expect(find.byType(LockScreen), findsNothing);

    await backgroundAndResume(tester);
    await pumpFrames(tester);

    expect(find.byType(LockScreen), findsOneWidget);
  });

  testWidgets('does not re-lock within the grace period', (tester) async {
    await pumpApp(tester, grace: const Duration(hours: 1));

    await backgroundAndResume(tester);
    await pumpFrames(tester);

    expect(find.byType(LockScreen), findsNothing);
  });

  testWidgets('does not re-lock when app lock is disabled in settings',
      (tester) async {
    // Real Hive I/O must run outside the widget test's fake-async zone.
    await tester.runAsync(() => Hive.box(AppConstants.settingsBox)
        .put(AppConstants.keyAppLockEnabled, false));
    await pumpApp(tester);

    await backgroundAndResume(tester);
    await pumpFrames(tester);

    expect(find.byType(LockScreen), findsNothing);
  });

  testWidgets('inactive alone (biometric sheet, app switcher) never locks',
      (tester) async {
    await pumpApp(tester);

    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await pumpFrames(tester);

    expect(find.byType(LockScreen), findsNothing);
  });

  testWidgets('successful authentication clears the lock overlay',
      (tester) async {
    await pumpApp(tester, authResult: AuthResult.success, startLocked: true);
    // Auto-prompt fired on mount, stub returned success → unlocked.
    expect(find.byType(LockScreen), findsNothing);
  });

  testWidgets('lock overlay stays up while authentication is cancelled',
      (tester) async {
    await pumpApp(tester, authResult: AuthResult.cancelled, startLocked: true);
    expect(find.byType(LockScreen), findsOneWidget);
  });

  testWidgets('app snackbars cannot paint above the lock overlay',
      (tester) async {
    await pumpApp(tester); // unlocked, dashboard mounted

    await backgroundAndResume(tester);
    await pumpFrames(tester);
    expect(find.byType(LockScreen), findsOneWidget);

    // Simulate an async flow (e.g. a price refresh) completing after the
    // re-lock: the dashboard stays mounted beneath the overlay and reports
    // its result through the root ScaffoldMessenger — exactly what
    // dashboard_screen.dart does. The root messenger presents on every
    // Scaffold it manages, so without the lock's own ScaffoldMessenger the
    // snackbar (which can name failed symbols — the user's holdings) would
    // attach to the lock screen's Scaffold and render above the lock.
    final dashboardContext = tester.element(find.byType(DashboardScreen));
    ScaffoldMessenger.of(dashboardContext).showSnackBar(
      const SnackBar(
        content: Text('2 updated, RELIANCE.NS failed'),
        duration: Duration(milliseconds: 200),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.descendant(
          of: find.byType(LockScreen), matching: find.byType(SnackBar)),
      findsNothing,
    );

    // Let the snackbar expire so no timers outlive the test.
    await tester.pump(const Duration(seconds: 1));
    await pumpFrames(tester);
  });
}
