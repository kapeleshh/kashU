import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:kashu/data/models/asset.dart';
import 'package:kashu/data/models/asset_type.dart';
import 'package:kashu/data/models/portfolio_summary.dart';
import 'package:kashu/data/repositories/asset_repository.dart';
import 'package:kashu/services/price_history_service.dart';
import 'package:kashu/shared/providers/portfolio_provider.dart';

import '../../fixtures/sample_portfolio.dart';

class MockAssetRepository extends Mock implements AssetRepository {}

class MockPriceHistoryService extends Mock implements PriceHistoryService {}

Asset _asset({String id = 'a1', double quantity = 10, double price = 110}) {
  final created = DateTime(2024, 1, 1);
  return Asset(
    id: id,
    name: 'Asset $id',
    type: AssetType.stock,
    quantity: quantity,
    purchasePrice: 100,
    currentPrice: price,
    currency: 'INR',
    purchaseDate: created,
    createdAt: created,
    updatedAt: created,
  );
}

/// Yesterday: 10 units of a1 worth 1000 (price 100).
DailySnapshot _yesterday({bool withQuantities = true}) => DailySnapshot(
      date: DateTime.now().subtract(const Duration(days: 1)),
      total: 1000,
      assetValues: const {'a1': 1000},
      assetQuantities: withQuantities ? const {'a1': 10} : const {},
    );

void main() {
  Future<PortfolioSummary> summaryFor(
      List<Asset> assets, DailySnapshot snapshot) {
    final repo = MockAssetRepository();
    when(() => repo.getAllAssets()).thenReturn(assets);
    when(() => repo.getTopGainers()).thenReturn(const []);
    when(() => repo.getTopLosers()).thenReturn(const []);
    final history = MockPriceHistoryService();
    when(() => history.previousDaySnapshot()).thenReturn(snapshot);

    final container = ProviderContainer(overrides: [
      assetRepositoryProvider.overrideWithValue(repo),
      baseCurrencyProvider.overrideWith((ref) => 'INR'),
      priceHistoryServiceProvider.overrideWithValue(history),
    ]);
    addTearDown(container.dispose);
    return container.read(portfolioSummaryProvider.future);
  }

  group("today's change around a recorded sale", () {
    test('a price move on an unchanged holding is reported as is', () async {
      final summary = await summaryFor([_asset()], _yesterday());

      expect(summary.todaysChange, closeTo(100, 1e-9)); // 10 x (110 - 100)
      expect(summary.todaysChangePercentage, closeTo(10, 1e-9));
    });

    test('selling 4 of 10 is not a loss — only the price move counts',
        () async {
      final summary = await summaryFor([_asset(quantity: 6)], _yesterday());

      // Unscaled this would read 660 - 1000 = -340 "today".
      expect(summary.todaysChange, closeTo(60, 1e-9)); // 6 x (110 - 100)
      expect(summary.todaysChangePercentage, closeTo(10, 1e-9));
    });

    test('a full exit shows no change instead of the whole position lost',
        () async {
      final summary = await summaryFor([_asset(quantity: 0)], _yesterday());

      expect(summary.todaysChange, 0);
      expect(summary.totalAssets, 0); // no open positions left
    });

    test('older snapshots without quantities keep the plain comparison',
        () async {
      final summary = await summaryFor(
          [_asset(quantity: 6)], _yesterday(withQuantities: false));

      expect(summary.todaysChange, closeTo(660 - 1000, 1e-9));
    });
  });

  test('totalAssets counts open positions, not sold-out ones', () async {
    final summary = await summaryFor(
        [_asset(), _asset(id: 'a2', quantity: 0)], _yesterday());

    expect(summary.totalAssets, 1);
  });

  test('a mixed INR + USD portfolio is totalled in the base currency',
      () async {
    final repo = MockAssetRepository();
    when(() => repo.getAllAssets()).thenReturn(samplePortfolio());
    when(() => repo.getTopGainers()).thenReturn(const []);
    when(() => repo.getTopLosers()).thenReturn(const []);
    final history = MockPriceHistoryService();
    when(() => history.previousDaySnapshot()).thenReturn(null);
    final container = ProviderContainer(overrides: [
      assetRepositoryProvider.overrideWithValue(repo),
      baseCurrencyProvider.overrideWith((ref) => 'INR'),
      priceHistoryServiceProvider.overrideWithValue(history),
      exchangeRatesProvider.overrideWith((ref) async => sampleRates()),
    ]);
    addTearDown(container.dispose);

    final summary = await container.read(portfolioSummaryProvider.future);

    // Apple's $1,840 is ₹1,56,400, not ₹1,840.
    expect(summary.totalValue, closeTo(sampleTotalValueInr, 1e-6));
    expect(summary.assetAllocation[AssetType.stock],
        closeTo(sampleStockValueInr, 1e-6));
  });

  test('a snapshot round-trips its quantities through JSON', () {
    final snap = _yesterday();
    final back = DailySnapshot.fromJson(snap.toJson())!;

    expect(back.assetQuantities, {'a1': 10.0});
    expect(
        DailySnapshot.fromJson(_yesterday(withQuantities: false).toJson())!
            .assetQuantities,
        isEmpty);
  });
}
