import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:kashu/core/utils/currency_formatter.dart';
import 'package:kashu/data/models/asset.dart';
import 'package:kashu/data/models/asset_type.dart';
import 'package:kashu/data/repositories/asset_repository.dart';
import 'package:kashu/data/repositories/portfolio_write_service.dart';
import 'package:kashu/features/assets/asset_detail_screen.dart';
import 'package:kashu/services/currency_converter_service.dart';
import 'package:kashu/services/price_history_service.dart';
import 'package:kashu/shared/providers/portfolio_provider.dart';

class MockAssetRepository extends Mock implements AssetRepository {}

class MockPriceHistoryService extends Mock implements PriceHistoryService {}

class MockPortfolioWriteService extends Mock implements PortfolioWriteService {}

Asset _asset({double currentPrice = 100}) {
  final created = DateTime(2024, 1, 15);
  return Asset(
    id: 'a1',
    name: 'Reliance',
    symbol: 'RELIANCE.NS',
    type: AssetType.stock,
    quantity: 10,
    purchasePrice: 80,
    currentPrice: currentPrice,
    currency: 'INR',
    purchaseDate: created,
    createdAt: created,
    updatedAt: created,
  );
}

/// Stands in for the assets box: the repository writes a new object on every
/// update, which is exactly what left the old detail screen showing a stale
/// snapshot.
final _storedAssets = StateProvider<List<Asset>>((ref) => [_asset()]);

void main() {
  late ProviderContainer container;
  late MockAssetRepository repo;
  late MockPortfolioWriteService writes;

  setUpAll(() => registerFallbackValue(_asset()));

  setUp(() {
    repo = MockAssetRepository();
    writes = MockPortfolioWriteService();
    final history = MockPriceHistoryService();
    when(() => history.assetSeries(any())).thenReturn(const []);

    container = ProviderContainer(overrides: [
      allAssetsProvider.overrideWith((ref) => ref.watch(_storedAssets)),
      assetRepositoryProvider.overrideWithValue(repo),
      baseCurrencyProvider.overrideWith((ref) => 'INR'),
      exchangeRatesProvider.overrideWith((ref) async => ExchangeRateResult(
            base: 'USD',
            rates: const {'INR': 83.0},
            fetchedAt: DateTime(2024, 1, 15),
            success: true,
          )),
      priceHistoryServiceProvider.overrideWithValue(history),
      portfolioWriteServiceProvider.overrideWithValue(writes),
    ]);

    // Saving from Edit stores a fresh copy, as the real repository does.
    when(() => repo.updateAsset(any())).thenAnswer((inv) async {
      final saved = inv.positionalArguments.first as Asset;
      container.read(_storedAssets.notifier).state = [saved];
    });
  });

  tearDown(() => container.dispose());

  void store(List<Asset> assets) =>
      container.read(_storedAssets.notifier).state = assets;

  /// A home screen with a button that opens the detail screen, so tests can
  /// tell "detail closed" (home visible again) from "detail still open".
  Future<void> openDetail(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const AssetDetailScreen(assetId: 'a1'),
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
    expect(find.text('Reliance'), findsOneWidget);
  }

  testWidgets('shows the stored copy and follows later writes',
      (tester) async {
    await openDetail(tester);
    expect(find.text('₹100.00'), findsOneWidget); // CURRENT tile

    // A manual price update / refresh stores a new object under the same id.
    store([_asset(currentPrice: 150)]);
    await tester.pump();

    expect(find.text('₹150.00'), findsOneWidget);
    expect(find.text('₹100.00'), findsNothing);
  });

  testWidgets('closes itself once the asset is deleted', (tester) async {
    await openDetail(tester);

    store([]);
    await tester.pumpAndSettle();

    expect(find.text('open'), findsOneWidget);
    expect(find.byType(AssetDetailScreen), findsNothing);
  });

  testWidgets('backing out of Edit keeps the detail screen open',
      (tester) async {
    await openDetail(tester);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit asset'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Edit asset'), findsNothing);
    expect(find.byType(AssetDetailScreen), findsOneWidget);
    verifyNever(() => repo.updateAsset(any()));
  });

  testWidgets('a negative or infinite manual price is refused inline',
      (tester) async {
    await openDetail(tester);
    final priceField = find.byKey(const ValueKey('manual-price'));

    await tester.enterText(priceField, '-5');
    await tester.ensureVisible(find.text('Update'));
    await tester.tap(find.text('Update'));
    await tester.pump();
    expect(find.text("Can't be negative"), findsOneWidget);

    await tester.enterText(priceField, 'Infinity');
    await tester.tap(find.text('Update'));
    await tester.pump();
    expect(find.text('Enter a valid number'), findsOneWidget);

    verifyNever(() => repo.updateAssetPrice(any(), any()));
  });

  testWidgets('a valid manual price is saved', (tester) async {
    when(() => repo.updateAssetPrice(any(), any()))
        .thenAnswer((_) async {});
    await openDetail(tester);

    await tester.enterText(find.byKey(const ValueKey('manual-price')), '0');
    await tester.ensureVisible(find.text('Update'));
    await tester.tap(find.text('Update'));
    await tester.pump();

    verify(() => repo.updateAssetPrice('a1', 0)).called(1);
  });

  testWidgets('a failed price update says so plainly', (tester) async {
    when(() => repo.updateAssetPrice(any(), any()))
        .thenThrow(Exception('HiveError: Box has already been closed'));
    await openDetail(tester);

    await tester.enterText(find.byKey(const ValueKey('manual-price')), '120');
    await tester.ensureVisible(find.text('Update'));
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't update the price. Please try again."),
        findsOneWidget);
    expect(find.textContaining('HiveError'), findsNothing);
    expect(find.text('Price updated successfully'), findsNothing);
  });

  testWidgets('a failed delete says so and keeps the holding on screen',
      (tester) async {
    when(() => writes.deleteAssetWithTransactions(any()))
        .thenThrow(Exception('HiveError: Box has already been closed'));
    await openDetail(tester);

    await tester.ensureVisible(find.text('Delete'));
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't delete Reliance. Please try again."),
        findsOneWidget);
    expect(find.textContaining('HiveError'), findsNothing);
    expect(find.byType(AssetDetailScreen), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget); // usable again
  });

  testWidgets('a confirmed delete is written once and closes the detail',
      (tester) async {
    when(() => writes.deleteAssetWithTransactions(any())).thenAnswer((_) async {
      store([]);
    });
    await openDetail(tester);

    await tester.ensureVisible(find.text('Delete'));
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    verify(() => writes.deleteAssetWithTransactions('a1')).called(1);
    expect(find.byType(AssetDetailScreen), findsNothing);
  });

  testWidgets('a deposit with terms shows them and today\'s value',
      (tester) async {
    final start = DateTime(2020, 1, 1);
    final fd = Asset(
      id: 'a1',
      name: 'Reliance', // the name openDetail waits for
      type: AssetType.fixedDeposit,
      quantity: 1,
      purchasePrice: 100000,
      currentPrice: 100000, // frozen on the day it was added
      currency: 'INR',
      purchaseDate: start,
      createdAt: start,
      updatedAt: start,
      depositRatePercent: 10,
      depositMaturityDate: DateTime(2022, 1, 1),
      depositCompounding: 'yearly',
    );
    store([fd]);
    await openDetail(tester);

    // Matured: worth its maturity value, not the stored 100000.
    final value = CurrencyFormatter.formatCurrency(fd.currentValue, 'INR');
    expect(fd.currentValue, greaterThan(120000));
    expect(find.text(value), findsWidgets);
    expect(find.text('10.00% p.a. · Yearly'), findsOneWidget);
    expect(find.text('Matured on'), findsOneWidget);
    // Nothing to update by hand.
    expect(find.text('Update Prices'), findsNothing);
    expect(find.byKey(const ValueKey('manual-price')), findsNothing);
  });

  testWidgets('Edit gets the current price and saving closes the detail',
      (tester) async {
    await openDetail(tester);
    store([_asset(currentPrice: 150)]);
    await tester.pump();

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    // The form starts from the stored copy, not the one the screen opened on.
    expect(find.widgetWithText(TextFormField, '150.0'), findsOneWidget);

    await tester.ensureVisible(find.text('Update'));
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();

    final saved =
        verify(() => repo.updateAsset(captureAny())).captured.single as Asset;
    expect(saved.currentPrice, 150); // not the stale 100 written back
    expect(find.byType(AssetDetailScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}
