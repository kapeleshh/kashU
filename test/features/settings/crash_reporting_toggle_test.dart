import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:kashu/core/config/app_config.dart';
import 'package:kashu/core/constants/app_constants.dart';
import 'package:kashu/data/models/asset.dart';
import 'package:kashu/data/models/asset_type.dart';
import 'package:kashu/data/models/transaction.dart';
import 'package:kashu/data/models/transaction_type.dart';
import 'package:kashu/features/settings/settings_screen.dart';
import 'package:kashu/shared/providers/settings_providers.dart';

void main() {
  late Box settings;

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
    settings =
        await Hive.openBox(AppConstants.settingsBox, bytes: Uint8List(0));
  });

  tearDown(() async {
    await Hive.close();
  });

  Finder crashSwitch() =>
      find.widgetWithText(SwitchListTile, 'Help improve KashU');

  Future<void> pumpSettings(WidgetTester tester, {bool? available}) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        if (available != null)
          crashReportingAvailableProvider.overrideWithValue(available),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pump();
  }

  test('availability follows whether a Sentry DSN was compiled in', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(crashReportingAvailableProvider),
        AppConfig.isSentryEnabled);
  });

  testWidgets('a build without a DSN shows no crash-reporting switch',
      (tester) async {
    await pumpSettings(tester, available: false);
    expect(crashSwitch(), findsNothing);
    // The rest of the card is still there.
    expect(find.text('Base Currency'), findsOneWidget);
  });

  testWidgets('unoverridden, the switch follows the compiled-in config',
      (tester) async {
    await pumpSettings(tester);
    // `flutter test` passes no SENTRY_DSN, so this is the no-DSN case.
    expect(crashSwitch(),
        AppConfig.isSentryEnabled ? findsOneWidget : findsNothing);
  });

  testWidgets('a build with a DSN shows the opt-in, off until chosen',
      (tester) async {
    await pumpSettings(tester, available: true);
    expect(crashSwitch(), findsOneWidget);
    expect(tester.widget<SwitchListTile>(crashSwitch()).value, isFalse);

    await tester.tap(crashSwitch());
    await tester.pump();

    expect(tester.widget<SwitchListTile>(crashSwitch()).value, isTrue);
    expect(settings.get(AppConstants.keyCrashReportingEnabled), isTrue);
  });
}
