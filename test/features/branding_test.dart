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
import 'package:kashu/features/onboarding/onboarding_screen.dart';
import 'package:kashu/features/settings/settings_screen.dart';
import 'package:kashu/main.dart';
import 'package:kashu/services/auth_service.dart';
import 'package:kashu/services/currency_converter_service.dart';
import 'package:kashu/shared/providers/portfolio_provider.dart';
import 'package:kashu/shared/widgets/kashu_logo.dart';

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

/// The old monogram: a lone "K" anywhere means a screen was missed.
final _oldMonogram = find.text('K');

void main() {
  setUpAll(() {
    Hive.registerAdapter(AssetTypeAdapter());
    Hive.registerAdapter(TransactionTypeAdapter());
    Hive.registerAdapter(AssetAdapter());
    Hive.registerAdapter(TransactionAdapter());
  });

  setUp(() async {
    await Hive.openBox<Asset>(AppConstants.assetsBox, bytes: Uint8List(0));
    await Hive.openBox<Transaction>(AppConstants.transactionsBox,
        bytes: Uint8List(0));
    await Hive.openBox(AppConstants.priceCacheBox, bytes: Uint8List(0));
    await Hive.openBox(AppConstants.priceHistoryBox, bytes: Uint8List(0));
    final settings =
        await Hive.openBox(AppConstants.settingsBox, bytes: Uint8List(0));
    await settings.put(AppConstants.keyOnboardingComplete, true);
  });

  tearDown(() async {
    await Hive.close();
  });

  Future<void> launch(WidgetTester tester,
      {bool onboarding = false, bool locked = false, String theme = 'light'}) async {
    tester.view.physicalSize = const Size(1440, 3040);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await Hive.box(AppConstants.settingsBox)
        .put(AppConstants.keyThemeMode, theme);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(_StubAuthService()),
        appLockedProvider.overrideWith((ref) => locked),
        exchangeRatesProvider
            .overrideWith((ref) async => ExchangeRateResult.failure('test')),
      ],
      child: KashUApp(showOnboarding: onboarding),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  for (final theme in ['light', 'dark']) {
    testWidgets('onboarding shows the new mark ($theme)', (tester) async {
      await launch(tester, onboarding: true, theme: theme);

      expect(find.descendant(
              of: find.byType(OnboardingScreen),
              matching: find.byType(KashuMark)),
          findsOneWidget);
      expect(_oldMonogram, findsNothing);
    });

    testWidgets('the lock screen shows the mark and wordmark ($theme)',
        (tester) async {
      await launch(tester, locked: true, theme: theme);

      final lock = find.byType(LockScreen);
      expect(find.descendant(of: lock, matching: find.byType(KashuMark)),
          findsOneWidget);
      expect(find.descendant(of: lock, matching: find.byType(KashuWordmark)),
          findsOneWidget);
      expect(_oldMonogram, findsNothing);
    });
  }

  testWidgets('Settings › About shows the mark and wordmark', (tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pump();
    await tester.scrollUntilVisible(find.byType(KashuWordmark), 300);

    expect(find.byType(KashuMark), findsOneWidget);
    expect(find.byType(KashuWordmark), findsOneWidget);
    expect(_oldMonogram, findsNothing);
  });
}
