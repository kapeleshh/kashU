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
import 'package:kashu/features/settings/settings_screen.dart';

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
    await Hive.openBox(AppConstants.settingsBox, bytes: Uint8List(0));
  });

  tearDown(() async {
    await Hive.close();
  });

  testWidgets('Settings links the privacy policy and shows the contact email',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pump();

    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text(AppConstants.contactEmail), findsOneWidget);
  });

  test('the policy URL is the page the web build publishes', () {
    expect(AppConstants.privacyPolicyUrl,
        'https://kash-u.vercel.app/privacy.html');
    expect(AppConstants.contactEmail, contains('@'));
  });
}
