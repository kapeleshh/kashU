import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:kashu/data/models/asset.dart';
import 'package:kashu/data/models/asset_type.dart';
import 'package:kashu/data/repositories/asset_repository.dart';
import 'package:kashu/data/repositories/portfolio_write_service.dart';
import 'package:kashu/features/assets/add_asset_screen.dart';
import 'package:kashu/services/gold_price_service.dart';
import 'package:kashu/shared/providers/portfolio_provider.dart';

class MockGoldPriceService extends Mock implements GoldPriceService {}

class MockAssetRepository extends Mock implements AssetRepository {}

class MockPortfolioWriteService extends Mock implements PortfolioWriteService {}

Asset _stock() {
  final bought = DateTime(2024, 1, 15);
  return Asset(
    id: 'a1',
    name: 'Reliance Industries',
    symbol: 'RELIANCE.NS',
    type: AssetType.stock,
    quantity: 10,
    purchasePrice: 2500,
    currentPrice: 2900,
    currency: 'INR',
    purchaseDate: bought,
    platform: 'Zerodha',
    notes: 'long term',
    createdAt: bought,
    updatedAt: bought,
  );
}

void main() {
  late MockGoldPriceService gold;
  late MockAssetRepository repo;
  late MockPortfolioWriteService writes;

  setUpAll(() => registerFallbackValue(_stock()));

  setUp(() {
    gold = MockGoldPriceService();
    repo = MockAssetRepository();
    writes = MockPortfolioWriteService();
    // Offline: the live metal price never arrives, the form must not care.
    when(() => gold.fetchGoldPriceBreakdown(
          targetCurrency: any(named: 'targetCurrency'),
        )).thenAnswer((_) async => null);
    when(() => gold.fetchSilverPriceBreakdown(
          targetCurrency: any(named: 'targetCurrency'),
        )).thenAnswer((_) async => null);
  });

  Future<void> openForm(WidgetTester tester, {Asset? existing}) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        baseCurrencyProvider.overrideWith((ref) => 'INR'),
        goldPriceServiceProvider.overrideWithValue(gold),
        assetRepositoryProvider.overrideWithValue(repo),
        portfolioWriteServiceProvider.overrideWithValue(writes),
      ],
      // Opened from a launcher so a finished save can be seen popping it.
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AddAssetScreen(existingAsset: existing),
                )),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> fillValidStock(WidgetTester tester) async {
    await tester.enterText(
        find.byKey(const ValueKey('asset-name')), 'Reliance Industries');
    await tester.enterText(find.byKey(const ValueKey('asset-quantity')), '10');
    await tester.enterText(
        find.byKey(const ValueKey('asset-purchase-price')), '2500');
    await tester.enterText(
        find.byKey(const ValueKey('asset-current-price')), '2900');
  }

  Future<void> tapSave(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pump();
  }

  String text(WidgetTester tester, String key) => tester
      .widget<TextFormField>(find.byKey(ValueKey(key)))
      .controller!
      .text;

  Future<void> tapType(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  group('changing the asset type on a new asset', () {
    testWidgets('clears the stock details but keeps currency and notes',
        (tester) async {
      await openForm(tester);

      await tester.enterText(
          find.byKey(const ValueKey('asset-name')), 'Reliance Industries');
      await tester.enterText(
          find.byKey(const ValueKey('asset-quantity')), '10');
      await tester.enterText(
          find.byKey(const ValueKey('asset-purchase-price')), '2500');
      await tester.enterText(
          find.byKey(const ValueKey('asset-current-price')), '2900');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Notes (Optional)'), 'gift');
      await tester.tap(find.byKey(const ValueKey('asset-platform')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zerodha').last);
      await tester.pumpAndSettle();

      await tapType(tester, 'Metals');

      expect(text(tester, 'asset-name'), isEmpty);
      expect(text(tester, 'asset-quantity'), isEmpty);
      expect(text(tester, 'asset-purchase-price'), isEmpty);
      expect(text(tester, 'asset-current-price'), isEmpty);
      expect(find.text('Zerodha'), findsNothing);
      // Kept: true of any holding.
      expect(find.text('gift'), findsOneWidget);
      expect(find.text('INR (₹)'), findsOneWidget);
    });

    testWidgets('a metal still gets the gold and silver contracts',
        (tester) async {
      await openForm(tester);
      await tester.enterText(
          find.byKey(const ValueKey('asset-name')), 'Reliance Industries');

      await tapType(tester, 'Metals');
      expect(text(tester, 'asset-symbol'), 'GC=F');
      verify(() => gold.fetchGoldPriceBreakdown(targetCurrency: 'INR'))
          .called(1);

      await tester.tap(find.text('Silver'));
      await tester.pumpAndSettle();
      expect(text(tester, 'asset-symbol'), 'SI=F');
      verify(() => gold.fetchSilverPriceBreakdown(targetCurrency: 'INR'))
          .called(1);
    });

    testWidgets('a crypto holding does not inherit a stock symbol',
        (tester) async {
      await openForm(tester);
      await tapType(tester, 'Metals');
      await tester.enterText(
          find.byKey(const ValueKey('asset-symbol')), 'RELIANCE.NS');

      await tapType(tester, 'Crypto');

      expect(text(tester, 'asset-symbol'), isNot('RELIANCE.NS'));
      expect(text(tester, 'asset-symbol'), isNot('GC=F'));
    });

    testWidgets('re-selecting the same type keeps what was typed',
        (tester) async {
      await openForm(tester);
      await tester.enterText(
          find.byKey(const ValueKey('asset-quantity')), '10');

      await tapType(tester, 'Stocks');

      expect(text(tester, 'asset-quantity'), '10');
    });
  });

  group('number validation', () {
    testWidgets('NaN, Infinity and a negative price are refused inline',
        (tester) async {
      await openForm(tester);
      await tester.enterText(
          find.byKey(const ValueKey('asset-name')), 'Reliance Industries');
      await tester.enterText(
          find.byKey(const ValueKey('asset-quantity')), 'NaN');
      await tester.enterText(
          find.byKey(const ValueKey('asset-purchase-price')), 'Infinity');
      await tester.enterText(
          find.byKey(const ValueKey('asset-current-price')), '-5');

      await tester.ensureVisible(find.text('Add to portfolio'));
      await tester.tap(find.text('Add to portfolio'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid number'), findsNWidgets(2));
      expect(find.text("Can't be negative"), findsOneWidget);
      verifyNever(() => writes.addAssetWithBuyTransaction(any()));
    });

    testWidgets('a new holding needs a quantity above 0', (tester) async {
      await openForm(tester);
      await tester.enterText(
          find.byKey(const ValueKey('asset-quantity')), '0');

      await tester.ensureVisible(find.text('Add to portfolio'));
      await tester.tap(find.text('Add to portfolio'));
      await tester.pumpAndSettle();

      expect(find.text('Must be more than 0'), findsOneWidget);
      verifyNever(() => writes.addAssetWithBuyTransaction(any()));
    });
  });

  group('saving', () {
    testWidgets('Save is disabled while the write is in flight',
        (tester) async {
      final write = Completer<void>();
      when(() => writes.addAssetWithBuyTransaction(any()))
          .thenAnswer((_) => write.future);
      await openForm(tester);
      await fillValidStock(tester);

      await tapSave(tester, 'Add to portfolio');
      // The label gives way to a spinner; tapping there again is ignored.
      expect(find.text('Add to portfolio'), findsNothing);
      await tester.tap(find.byType(CircularProgressIndicator));
      await tester.pump();
      verify(() => writes.addAssetWithBuyTransaction(any())).called(1);

      write.complete();
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget); // form closed
      expect(find.text('Asset added & transaction logged'), findsOneWidget);
    });

    testWidgets('a failed add says so plainly and keeps the form',
        (tester) async {
      when(() => writes.addAssetWithBuyTransaction(any())).thenThrow(
          Exception('HiveError: Box has already been closed'));
      await openForm(tester);
      await fillValidStock(tester);

      await tapSave(tester, 'Add to portfolio');
      await tester.pumpAndSettle();

      expect(find.textContaining("Couldn't add this asset"), findsOneWidget);
      expect(find.textContaining('HiveError'), findsNothing);
      // Still on the form, with Save usable again.
      expect(find.text('open'), findsNothing);
      expect(find.text('Add to portfolio'), findsOneWidget);
      expect(text(tester, 'asset-name'), 'Reliance Industries');
    });

    testWidgets('a failed edit says so plainly and keeps the form',
        (tester) async {
      when(() => repo.updateAsset(any()))
          .thenThrow(Exception('FileSystemException: No space left'));
      await openForm(tester, existing: _stock());

      await tapSave(tester, 'Update');
      await tester.pumpAndSettle();

      expect(find.textContaining("Couldn't save your changes"),
          findsOneWidget);
      expect(find.textContaining('FileSystemException'), findsNothing);
      expect(find.text('Update'), findsOneWidget);
    });

    testWidgets('a failed delete from Edit says so and keeps the form',
        (tester) async {
      when(() => writes.deleteAssetWithTransactions(any()))
          .thenThrow(Exception('HiveError'));
      await openForm(tester, existing: _stock());

      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't delete this asset. Please try again."),
          findsOneWidget);
      expect(find.text('Edit asset'), findsOneWidget);
    });
  });

  group('changing the asset type while editing', () {
    testWidgets('cancelling the confirmation keeps the old type and fields',
        (tester) async {
      await openForm(tester, existing: _stock());

      await tapType(tester, 'Metals');
      expect(find.text('Change asset type?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(text(tester, 'asset-name'), 'Reliance Industries');
      expect(text(tester, 'asset-symbol'), 'RELIANCE.NS');
      expect(text(tester, 'asset-quantity'), '10.0');
      verifyNever(() => gold.fetchGoldPriceBreakdown(
            targetCurrency: any(named: 'targetCurrency'),
          ));
    });

    testWidgets('confirming clears the type-specific fields', (tester) async {
      await openForm(tester, existing: _stock());

      await tapType(tester, 'Metals');
      await tester.tap(find.text('Change type'));
      await tester.pumpAndSettle();

      expect(text(tester, 'asset-name'), isEmpty);
      expect(text(tester, 'asset-quantity'), isEmpty);
      expect(text(tester, 'asset-purchase-price'), isEmpty);
      expect(text(tester, 'asset-symbol'), 'GC=F');
      expect(find.text('Zerodha'), findsNothing);
      expect(find.text('long term'), findsOneWidget);
    });
  });
}
