import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:kashu/data/models/asset.dart';
import 'package:kashu/data/models/asset_type.dart';
import 'package:kashu/data/models/transaction.dart';
import 'package:kashu/data/models/transaction_type.dart';
import 'package:kashu/data/repositories/portfolio_write_service.dart';
import 'package:kashu/data/repositories/transaction_repository.dart';
import 'package:kashu/features/transactions/record_transaction_sheet.dart';
import 'package:kashu/features/transactions/transactions_screen.dart';
import 'package:kashu/services/currency_converter_service.dart';
import 'package:kashu/shared/providers/portfolio_provider.dart';

class MockPortfolioWriteService extends Mock implements PortfolioWriteService {}

class MockTransactionRepository extends Mock implements TransactionRepository {}

Asset _asset({double quantity = 10}) {
  final bought = DateTime(2024, 1, 15);
  return Asset(
    id: 'a1',
    name: 'Reliance',
    type: AssetType.stock,
    quantity: quantity,
    purchasePrice: 100,
    currentPrice: 120,
    currency: 'INR',
    purchaseDate: bought,
    createdAt: bought,
    updatedAt: bought,
  );
}

Transaction _tx(TransactionType type, double amount, DateTime date) =>
    Transaction(
      id: '${type.name}-$amount',
      assetId: 'a1',
      type: type,
      quantity: type == TransactionType.buy ? 10 : 0,
      price: type == TransactionType.buy ? 100 : 0,
      amount: amount,
      currency: 'INR',
      date: date,
      createdAt: date,
    );

void main() {
  late MockPortfolioWriteService writes;

  setUp(() {
    writes = MockPortfolioWriteService();
  });

  void useTallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  group('Record transaction sheet', () {
    Future<void> openSheet(WidgetTester tester, Asset asset) async {
      useTallView(tester);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          allAssetsProvider.overrideWithValue([asset]),
          portfolioWriteServiceProvider.overrideWithValue(writes),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () =>
                      showRecordTransactionSheet(context, assetId: 'a1'),
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

    Finder field(String key) => find.byKey(ValueKey(key));

    testWidgets('refuses an over-sell inline and writes nothing',
        (tester) async {
      await openSheet(tester, _asset());

      await tester.enterText(field('sell-quantity'), '12');
      await tester.tap(find.text('Record sale'));
      await tester.pump();

      expect(find.text('You hold 10'), findsOneWidget);
      verifyNever(() => writes.recordSell(
            assetId: any(named: 'assetId'),
            quantity: any(named: 'quantity'),
            pricePerUnit: any(named: 'pricePerUnit'),
            date: any(named: 'date'),
            notes: any(named: 'notes'),
          ));
    });

    testWidgets('flags non-numeric and zero input', (tester) async {
      await openSheet(tester, _asset());

      await tester.enterText(field('sell-quantity'), 'abc');
      await tester.enterText(field('sell-price'), '0');
      await tester.tap(find.text('Record sale'));
      await tester.pump();

      expect(find.text('Enter a valid number'), findsOneWidget);
      expect(find.text('Must be more than 0'), findsOneWidget);
    });

    testWidgets('records a valid sale and closes with feedback',
        (tester) async {
      when(() => writes.recordSell(
                assetId: any(named: 'assetId'),
                quantity: any(named: 'quantity'),
                pricePerUnit: any(named: 'pricePerUnit'),
                date: any(named: 'date'),
                notes: any(named: 'notes'),
              ))
          .thenAnswer((_) async =>
              _tx(TransactionType.sell, 520, DateTime(2024, 6, 1)));
      await openSheet(tester, _asset());

      await tester.enterText(field('sell-quantity'), '4');
      await tester.enterText(field('sell-price'), '130');
      await tester.pump();
      expect(find.text('Proceeds ₹520.00'), findsOneWidget);

      await tester.tap(find.text('Record sale'));
      await tester.pumpAndSettle();

      verify(() => writes.recordSell(
            assetId: 'a1',
            quantity: 4,
            pricePerUnit: 130,
            date: any(named: 'date'),
            notes: any(named: 'notes'),
          )).called(1);
      expect(find.text('Record sale'), findsNothing); // sheet closed
      expect(find.textContaining('Sale recorded'), findsOneWidget);
    });

    testWidgets('a sold-out holding defaults to income', (tester) async {
      await openSheet(tester, _asset(quantity: 0));

      expect(find.text('Dividend received'), findsOneWidget);
      expect(field('sell-quantity'), findsNothing);
    });
  });

  group('Activity list', () {
    Future<void> pumpActivity(
        WidgetTester tester, List<Transaction> transactions) async {
      useTallView(tester);
      final repo = MockTransactionRepository();
      when(() => repo.getAllTransactions()).thenReturn(transactions);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          allAssetsProvider.overrideWithValue([_asset()]),
          transactionRepositoryProvider.overrideWithValue(repo),
          baseCurrencyProvider.overrideWith((ref) => 'INR'),
          exchangeRatesProvider.overrideWith(
              (ref) async => ExchangeRateResult.failure('offline in tests')),
        ],
        child: const MaterialApp(home: TransactionsScreen()),
      ));
      await tester.pump();
    }

    Text amountText(WidgetTester tester, String starts) => tester
        .widgetList<Text>(find.byType(Text))
        .firstWhere((t) => (t.data ?? '').startsWith(starts));

    testWidgets('a buy is money out, income is money in, dates have a year',
        (tester) async {
      await pumpActivity(tester, [
        _tx(TransactionType.buy, 1000, DateTime(2024, 1, 15)),
        _tx(TransactionType.dividend, 25, DateTime(2024, 3, 5)),
      ]);

      final buy = amountText(tester, '-₹1,000.00');
      final dividend = amountText(tester, '+₹25.00');
      final context = tester.element(find.byType(TransactionsScreen));
      // Paying for an asset is not a loss: no loss colour on the buy.
      expect(buy.style?.color, Theme.of(context).colorScheme.onSurface);
      expect(dividend.style?.color, isNot(buy.style?.color));

      expect(find.text('15 Jan 2024'), findsOneWidget);
      expect(find.text('5 Mar 2024'), findsOneWidget);
    });
  });
}
