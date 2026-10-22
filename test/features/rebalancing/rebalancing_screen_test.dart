import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';

import 'package:kashu/core/constants/app_constants.dart';
import 'package:kashu/core/utils/currency_formatter.dart';
import 'package:kashu/data/repositories/asset_repository.dart';
import 'package:kashu/features/rebalancing/rebalancing_screen.dart';
import 'package:kashu/services/price_history_service.dart';
import 'package:kashu/shared/providers/portfolio_provider.dart';

import '../../fixtures/sample_portfolio.dart';

class MockAssetRepository extends Mock implements AssetRepository {}

class MockPriceHistoryService extends Mock implements PriceHistoryService {}

void main() {
  setUp(() async {
    // Target allocations are read from the settings box.
    await Hive.openBox(AppConstants.settingsBox, bytes: Uint8List(0));
  });

  tearDown(() async {
    await Hive.close();
  });

  Future<ProviderContainer> pumpRebalancing(WidgetTester tester) async {
    final repo = MockAssetRepository();
    when(() => repo.getAllAssets()).thenReturn(samplePortfolio());
    when(() => repo.getTopGainers()).thenReturn(const []);
    when(() => repo.getTopLosers()).thenReturn(const []);
    final history = MockPriceHistoryService();
    when(() => history.previousDaySnapshot()).thenReturn(null);

    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: [
      assetRepositoryProvider.overrideWithValue(repo),
      baseCurrencyProvider.overrideWith((ref) => 'INR'),
      priceHistoryServiceProvider.overrideWithValue(history),
      exchangeRatesProvider.overrideWith((ref) async => sampleRates()),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: RebalancingScreen()),
    ));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
      'a USD holding is converted, so the total and split match the dashboard',
      (tester) async {
    final container = await pumpRebalancing(tester);
    final summary = await container.read(portfolioSummaryProvider.future);

    // Same total as the dashboard's hero card (₹21,21,753.60, not the
    // ₹19,67,193.60 an unconverted sum gives).
    expect(summary.totalValue, closeTo(sampleTotalValueInr, 1e-6));
    expect(
      find.text(CurrencyFormatter.formatCurrency(summary.totalValue, 'INR')),
      findsOneWidget,
    );

    // Stocks are 19.0% — Apple counted at ₹1,56,400 rather than ₹1,840.
    final stockPct = sampleStockValueInr / sampleTotalValueInr * 100;
    expect(stockPct.toStringAsFixed(1), '19.0');
    expect(find.text('now 19.0%'), findsOneWidget);
  });

  testWidgets('rebalancing amounts are in the base currency', (tester) async {
    // Everything in stocks: the action is to buy the rest of the
    // portfolio's (converted) value in stocks.
    await Hive.box(AppConstants.settingsBox).put('rebal_stock', 100.0);

    await pumpRebalancing(tester);

    final buy = sampleTotalValueInr - sampleStockValueInr;
    expect(
      find.text('Buy ${CurrencyFormatter.formatCurrency(buy, 'INR')}'),
      findsOneWidget,
    );
  });
}
