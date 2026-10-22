import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:kashu/features/onboarding/onboarding_screen.dart';
import 'package:kashu/features/settings/settings_screen.dart';
import 'package:kashu/main.dart';
import 'package:kashu/services/auth_service.dart';
import 'package:kashu/services/currency_converter_service.dart';
import 'package:kashu/shared/providers/portfolio_provider.dart';

/// Never prompts; a cancelled prompt keeps the lock screen up.
class _StubAuthService implements AuthService {
  @override
  Future<AuthResult> authenticate(
          {String reason = 'Authenticate to open KashU'}) async =>
      AuthResult.cancelled;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> isEnrolled() async => true;
}

/// Bounded frames — the dashboard's mascot animation never settles. Long
/// enough for MaterialApp's theme cross-fade to finish.
Future<void> pumpFrames(WidgetTester tester, [int frames = 5]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late Box settings;

  setUpAll(() {
    Hive.registerAdapter(AssetTypeAdapter());
    Hive.registerAdapter(TransactionTypeAdapter());
    Hive.registerAdapter(AssetAdapter());
    Hive.registerAdapter(TransactionAdapter());
  });

  setUp(() async {
    // In-memory boxes: writes complete inside the widget test's fake-async
    // zone, and the same box outlives a "restart" of the widget tree.
    await Hive.openBox<Asset>(AppConstants.assetsBox, bytes: Uint8List(0));
    await Hive.openBox<Transaction>(AppConstants.transactionsBox,
        bytes: Uint8List(0));
    await Hive.openBox(AppConstants.priceCacheBox, bytes: Uint8List(0));
    await Hive.openBox(AppConstants.priceHistoryBox, bytes: Uint8List(0));
    settings =
        await Hive.openBox(AppConstants.settingsBox, bytes: Uint8List(0));
    await settings.put(AppConstants.keyOnboardingComplete, true);
  });

  tearDown(() async {
    await Hive.close();
  });

  /// Starts the real app widget, as main() does after bootstrap.
  Future<void> launchApp(
    WidgetTester tester, {
    bool showOnboarding = false,
    bool locked = false,
  }) async {
    tester.view.physicalSize = const Size(1440, 3040);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(_StubAuthService()),
        appLockedProvider.overrideWith((ref) => locked),
        exchangeRatesProvider
            .overrideWith((ref) async => ExchangeRateResult.failure('test')),
      ],
      child: KashUApp(showOnboarding: showOnboarding),
    ));
    await pumpFrames(tester);
  }

  /// Kills the widget tree (and its ProviderScope), then launches again
  /// against the same settings box.
  Future<void> restartApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await launchApp(tester);
  }

  void setPhoneBrightness(WidgetTester tester, Brightness brightness) {
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  }

  Brightness brightnessOf(WidgetTester tester, Type screen) =>
      Theme.of(tester.element(find.byType(screen))).brightness;

  Finder option(String title) =>
      find.widgetWithText(RadioListTile<ThemeMode>, title);

  Future<void> choose(WidgetTester tester, String title) async {
    await tester.ensureVisible(option(title));
    await tester.tap(option(title));
    await pumpFrames(tester);
  }

  /// Exactly [title] reads as the checked radio, as a screen reader sees it.
  void expectSelected(WidgetTester tester, String title) {
    for (final each in ['System', 'Light', 'Dark']) {
      expect(tester.getSemantics(option(each)),
          isSemantics(isChecked: each == title),
          reason: each);
    }
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.settings_rounded));
    await pumpFrames(tester);
    expect(find.text('Appearance'), findsOneWidget);
  }

  testWidgets('System is the default and follows the phone', (tester) async {
    setPhoneBrightness(tester, Brightness.dark);
    await launchApp(tester);
    expect(brightnessOf(tester, DashboardScreen), Brightness.dark);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await pumpFrames(tester);
    expect(brightnessOf(tester, DashboardScreen), Brightness.light);

    await openSettings(tester);
    expectSelected(tester, 'System');
  });

  testWidgets(
      'Dark applies at once, survives a restart, and System hands back '
      'to the phone', (tester) async {
    setPhoneBrightness(tester, Brightness.light);
    await launchApp(tester);
    await openSettings(tester);
    expect(brightnessOf(tester, SettingsScreen), Brightness.light);

    // Choose Dark: the whole app flips without a restart.
    await choose(tester, 'Dark');
    expect(brightnessOf(tester, SettingsScreen), Brightness.dark);
    expect(brightnessOf(tester, DashboardScreen), Brightness.dark);
    expect(settings.get(AppConstants.keyThemeMode), 'dark');

    // Restart: a fresh provider scope reads the choice back from the box,
    // and the phone being in light mode does not override it.
    await restartApp(tester);
    expect(brightnessOf(tester, DashboardScreen), Brightness.dark);

    // Back to System: follows the phone again, both ways.
    await openSettings(tester);
    expectSelected(tester, 'Dark');
    await choose(tester, 'System');
    expectSelected(tester, 'System');
    expect(brightnessOf(tester, SettingsScreen), Brightness.light);
    expect(settings.get(AppConstants.keyThemeMode), 'system');

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await pumpFrames(tester);
    expect(brightnessOf(tester, SettingsScreen), Brightness.dark);
  });

  testWidgets('Light holds even when the phone is dark', (tester) async {
    setPhoneBrightness(tester, Brightness.dark);
    await launchApp(tester);
    await openSettings(tester);

    await choose(tester, 'Light');
    expectSelected(tester, 'Light');
    expect(brightnessOf(tester, SettingsScreen), Brightness.light);
    expect(settings.get(AppConstants.keyThemeMode), 'light');
  });

  testWidgets('the saved choice also themes onboarding', (tester) async {
    setPhoneBrightness(tester, Brightness.light);
    await settings.put(AppConstants.keyThemeMode, 'dark');

    await launchApp(tester, showOnboarding: true);
    expect(brightnessOf(tester, OnboardingScreen), Brightness.dark);
  });

  testWidgets('the saved choice also themes the lock screen', (tester) async {
    setPhoneBrightness(tester, Brightness.dark);
    await settings.put(AppConstants.keyThemeMode, 'light');

    await launchApp(tester, locked: true);
    expect(find.byType(LockScreen), findsOneWidget);
    expect(brightnessOf(tester, LockScreen), Brightness.light);
  });

  testWidgets('status-bar icons follow the theme on the AppBar-less home',
      (tester) async {
    setPhoneBrightness(tester, Brightness.dark);
    await settings.put(AppConstants.keyThemeMode, 'light');
    await launchApp(tester);
    // Light theme → dark icons, or they vanish into the light background.
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.dark);

    await openSettings(tester);
    await choose(tester, 'Dark');
    await tester.tap(find.byIcon(Icons.home_rounded));
    await pumpFrames(tester);
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.light);
  });
}
