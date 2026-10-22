import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';

import 'package:kashu/core/constants/app_constants.dart';
import 'package:kashu/data/models/asset.dart';
import 'package:kashu/data/models/asset_type.dart';
import 'package:kashu/data/models/transaction.dart';
import 'package:kashu/data/models/transaction_type.dart';
import 'package:kashu/data/repositories/portfolio_write_service.dart';
import 'package:kashu/features/settings/settings_screen.dart';
import 'package:kashu/shared/providers/portfolio_provider.dart';

class MockPortfolioWriteService extends Mock implements PortfolioWriteService {}

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

  Future<void> clearAllFromSettings(
      WidgetTester tester, PortfolioWriteService writes) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [portfolioWriteServiceProvider.overrideWithValue(writes)],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pump();

    await tester.scrollUntilVisible(find.text('Clear All Data'), 200);
    await tester.tap(find.text('Clear All Data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear All'));
    await tester.pumpAndSettle();
  }

  testWidgets('a successful clear says so', (tester) async {
    final writes = MockPortfolioWriteService();
    when(writes.clearAllData).thenAnswer((_) async {});

    await clearAllFromSettings(tester, writes);

    verify(writes.clearAllData).called(1);
    expect(find.text('All data cleared'), findsOneWidget);
  });

  testWidgets('a failed clear shows a plain message, not the exception',
      (tester) async {
    final writes = MockPortfolioWriteService();
    when(writes.clearAllData).thenThrow(HiveError('disk full at /data/x'));

    await clearAllFromSettings(tester, writes);

    expect(find.text("Couldn't clear all your data. Please try again."),
        findsOneWidget);
    expect(find.text('All data cleared'), findsNothing);
    expect(find.textContaining('disk full'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing); // dialog closed
  });
}
