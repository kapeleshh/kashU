import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:kashu/core/constants/app_constants.dart';
import 'package:kashu/data/models/asset.dart';
import 'package:kashu/data/models/asset_type.dart';
import 'package:kashu/data/models/transaction.dart';
import 'package:kashu/data/models/transaction_type.dart';
import 'package:kashu/data/repositories/asset_repository.dart';
import 'package:kashu/data/repositories/portfolio_write_service.dart';
import 'package:kashu/data/repositories/transaction_repository.dart';
import 'package:kashu/services/base_currency_converter.dart';
import 'package:kashu/services/export_service.dart';

import '../fixtures/sample_portfolio.dart';

Asset _asset({
  String id = 'a1',
  String name = 'Reliance',
  String? symbol = 'RELIANCE.NS',
  AssetType type = AssetType.stock,
  double qty = 10,
  double buy = 100,
  double cur = 130,
  String currency = 'INR',
  String? platform = 'Zerodha',
  DateTime? purchaseDate,
}) {
  final now = DateTime(2024, 1, 1);
  return Asset(
    id: id,
    name: name,
    symbol: symbol,
    type: type,
    quantity: qty,
    purchasePrice: buy,
    currentPrice: cur,
    currency: currency,
    purchaseDate: purchaseDate ?? DateTime(2023, 1, 1),
    platform: platform,
    createdAt: now,
    updatedAt: now,
  );
}

Transaction _sell({
  String id = 't1',
  String assetId = 'a1',
  double qty = 5,
  double price = 130,
  double amount = 650,
  String currency = 'INR',
  required DateTime date,
}) =>
    Transaction(
      id: id,
      assetId: assetId,
      type: TransactionType.sell,
      quantity: qty,
      price: price,
      amount: amount,
      currency: currency,
      date: date,
      createdAt: DateTime(2024, 1, 1),
    );

void main() {
  group('ExportService.computeCapitalGains', () {
    test('computes cost basis, proceeds and gain for a sell', () {
      final asset = _asset(buy: 100, purchaseDate: DateTime(2023, 1, 1));
      final sell = _sell(qty: 5, amount: 650, date: DateTime(2023, 6, 1));

      final rows = ExportService.computeCapitalGains(
          [asset], [sell], {'a1': 'Reliance'});

      expect(rows, hasLength(1));
      final r = rows.single;
      expect(r.costBasis, 5 * 100); // qty × avg buy price
      expect(r.saleProceeds, 650);
      expect(r.gain, 650 - 500); // +150
      expect(r.assetName, 'Reliance');
      expect(r.assetType, AssetType.stock);
    });

    test('a loss produces a negative gain', () {
      final asset = _asset(buy: 200);
      final sell = _sell(qty: 5, amount: 800, date: DateTime(2023, 6, 1));
      final r = ExportService.computeCapitalGains([asset], [sell], {}).single;
      expect(r.costBasis, 1000);
      expect(r.gain, -200);
    });

    test('LTCG boundary: >= 365 holding days is long-term, 364 is short', () {
      final asset = _asset(purchaseDate: DateTime(2023, 1, 1));
      final longTerm = ExportService.computeCapitalGains(
        [asset],
        [_sell(id: 'lt', date: DateTime(2024, 1, 1))], // 365 days
        {},
      ).single;
      final shortTerm = ExportService.computeCapitalGains(
        [asset],
        [_sell(id: 'st', date: DateTime(2023, 12, 31))], // 364 days
        {},
      ).single;

      expect(longTerm.holdingDays, 365);
      expect(longTerm.isLongTerm, isTrue);
      expect(shortTerm.holdingDays, 364);
      expect(shortTerm.isLongTerm, isFalse);
    });

    test('sells with no matching asset are skipped', () {
      final rows = ExportService.computeCapitalGains(
        [_asset(id: 'a1')],
        [_sell(assetId: 'ghost', date: DateTime(2023, 6, 1))],
        {},
      );
      expect(rows, isEmpty);
    });

    test('non-sell transactions are ignored', () {
      final asset = _asset(id: 'a1');
      final buy = Transaction(
        id: 'b1',
        assetId: 'a1',
        type: TransactionType.buy,
        quantity: 10,
        price: 100,
        amount: 1000,
        currency: 'INR',
        date: DateTime(2023, 1, 1),
        createdAt: DateTime(2024, 1, 1),
      );
      final dividend = Transaction(
        id: 'd1',
        assetId: 'a1',
        type: TransactionType.dividend,
        quantity: 0,
        price: 0,
        amount: 50,
        currency: 'INR',
        date: DateTime(2023, 3, 1),
        createdAt: DateTime(2024, 1, 1),
      );
      final rows = ExportService.computeCapitalGains(
          [asset], [buy, dividend], {});
      expect(rows, isEmpty);
    });

    test('multiple sells are returned oldest → newest', () {
      final asset = _asset(id: 'a1');
      final rows = ExportService.computeCapitalGains(
        [asset],
        [
          _sell(id: 's2', date: DateTime(2023, 8, 1)),
          _sell(id: 's1', date: DateTime(2023, 5, 1)),
        ],
        {},
      );
      expect(rows.map((r) => r.saleDate),
          [DateTime(2023, 5, 1), DateTime(2023, 8, 1)]);
    });
  });

  // The PDF's totals carry a base-currency label, so a USD holding in an
  // INR portfolio has to be converted before it is added in.
  group('PDF totals of a mixed INR + USD portfolio', () {
    final fx = BaseCurrencyConverter(base: 'INR', rates: sampleRates());

    test('portfolio totals are in the base currency, matching the dashboard',
        () {
      final totals = ExportService.portfolioTotals(samplePortfolio(), fx);

      expect(totals.value, closeTo(sampleTotalValueInr, 1e-6));
      final invested = samplePortfolio()
          .fold(0.0, (s, a) => s + fx.investedOf(a));
      expect(totals.invested, closeTo(invested, 1e-6));
      expect(totals.gain, closeTo(sampleTotalValueInr - invested, 1e-6));
    });

    test('STCG and LTCG add each sale in the base currency', () {
      final gains = ExportService.computeCapitalGains(
        [
          _asset(id: 'inr', buy: 100, purchaseDate: DateTime(2023, 1, 1)),
          _asset(
              id: 'usd',
              buy: 100,
              currency: 'USD',
              purchaseDate: DateTime(2023, 1, 1)),
        ],
        [
          // +150 INR, short term
          _sell(id: 's1', assetId: 'inr', amount: 650,
              date: DateTime(2023, 6, 1)),
          // +$10 short term, and +$50 long term
          _sell(id: 's2', assetId: 'usd', amount: 510, currency: 'USD',
              date: DateTime(2023, 6, 1)),
          _sell(id: 's3', assetId: 'usd', amount: 550, currency: 'USD',
              date: DateTime(2024, 6, 1)),
        ],
        {},
      );

      final totals = ExportService.capitalGainsTotals(gains, fx);

      expect(totals.shortTerm, closeTo(150 + 10 * usdInr, 1e-6));
      expect(totals.longTerm, closeTo(50 * usdInr, 1e-6));
    });

    test('the report lays out and saves', () async {
      final assets = samplePortfolio();
      final doc = ExportService.buildCapitalGainsPdf(
        assets,
        [
          _sell(assetId: 'aapl', qty: 2, price: 230, amount: 460,
              currency: 'USD', date: DateTime(2024, 9, 1)),
        ],
        {for (final a in assets) a.id: a.name},
        fx,
      );

      expect(await doc.save(), isNotEmpty);
    });
  });

  group('ExportService.holdingsCsvRows', () {
    test('header + one row per asset with correct columns', () {
      final rows = ExportService.holdingsCsvRows([_asset()]);
      expect(rows.first,
          containsAll(<String>['Name', 'Symbol', 'Invested', 'Gain/Loss %']));
      final data = rows[1];
      expect(data[0], 'Reliance'); // Name
      expect(data[1], 'RELIANCE.NS'); // Symbol
      expect(data[8], '1000.00'); // Invested = 10 × 100
      expect(data[9], '1300.00'); // Current Value = 10 × 130
      expect(data[10], '300.00'); // Gain/Loss
      expect(data[11], '30.00%'); // Gain/Loss %
    });

    test("a deposit with terms shows today's price, not the stored one", () {
      final now = DateTime.now();
      final opened = DateTime(now.year - 1, now.month, now.day);
      final fd = Asset(
        id: 'fd',
        name: 'SBI FD',
        type: AssetType.fixedDeposit,
        quantity: 1,
        purchasePrice: 100000,
        currentPrice: 100000, // stored the day it was added
        currency: 'INR',
        purchaseDate: opened,
        createdAt: opened,
        updatedAt: opened,
        depositRatePercent: 10,
        depositMaturityDate: DateTime(now.year + 2, now.month, now.day),
        depositCompounding: 'yearly',
      );

      final csv = ExportService.holdingsCsvRows([fd])[1];
      expect(csv[7], csv[9]); // Current Price = Current Value (1 unit)
      expect(double.parse(csv[7] as String), greaterThan(109000));
      expect(csv[6], csv[8]); // Avg Buy Price = Invested

      final pdf = ExportService.pdfHoldingsRows([fd]).single;
      expect(pdf[5], csv[7]);
    });

    test('null symbol/platform render as empty strings', () {
      final rows =
          ExportService.holdingsCsvRows([_asset(symbol: null, platform: null)]);
      expect(rows[1][1], ''); // Symbol
      expect(rows[1][3], ''); // Platform
    });
  });

  // A fully sold holding stays stored at quantity 0 so the capital-gains
  // report can find its cost basis, but it is no longer a holding.
  group('fully sold holdings', () {
    final open = _asset(id: 'open', name: 'Reliance');
    final sold = _asset(id: 'sold', name: 'Infosys', qty: 0, buy: 1400);
    final sale = _sell(
        id: 's1', assetId: 'sold', qty: 10, price: 1500, amount: 15000,
        date: DateTime(2023, 6, 1));

    test('are left out of the holdings CSV', () {
      final rows = ExportService.holdingsCsvRows([open, sold]);

      expect(rows, hasLength(2)); // header + the open holding
      expect(rows[1][0], 'Reliance');
    });

    test("are left out of the PDF's holdings section and count", () {
      final rows = ExportService.pdfHoldingsRows([open, sold]);

      expect(rows.map((r) => r.first), ['Reliance']);
      expect(ExportService.openHoldings([open, sold]), [open]);
    });

    test('still supply the cost basis of their capital gains', () {
      final gains = ExportService.computeCapitalGains(
          [open, sold], [sale], {'open': 'Reliance', 'sold': 'Infosys'});

      expect(gains.single.assetName, 'Infosys');
      expect(gains.single.costBasis, 14000); // 10 x 1400
      expect(gains.single.gain, 1000);
    });

    test('leave the totals unchanged', () {
      const fx = BaseCurrencyConverter(base: 'INR');
      final withSold = ExportService.portfolioTotals([open, sold], fx);
      final without = ExportService.portfolioTotals([open], fx);

      expect(withSold.value, without.value);
      expect(withSold.invested, without.invested);
    });

    test('the report still lays out with only sold holdings', () async {
      final doc = ExportService.buildCapitalGainsPdf(
        [sold],
        [sale],
        {'sold': 'Infosys'},
        const BaseCurrencyConverter(base: 'INR'),
      );

      expect(await doc.save(), isNotEmpty);
    });
  });

  group('ExportService.transactionsCsvRows', () {
    test('header + rows, asset name falls back to id when unknown', () {
      final tx = _sell(assetId: 'a1', date: DateTime(2023, 6, 1));
      final rows = ExportService.transactionsCsvRows([tx], {'a1': 'Reliance'});
      expect(rows.first.first, 'Date');
      expect(rows[1][1], 'Reliance'); // resolved name

      final rowsUnknown =
          ExportService.transactionsCsvRows([tx], <String, String>{});
      expect(rowsUnknown[1][1], 'a1'); // fallback to id
    });
  });

  // End to end through the real write path: a sale recorded in the app must
  // be exactly what the capital-gains report reads — including a full exit,
  // whose asset has to survive (at quantity 0) to supply the cost basis.
  group('a sale recorded through PortfolioWriteService', () {
    late Directory tempDir;
    late AssetRepository assetRepo;
    late TransactionRepository txRepo;
    late PortfolioWriteService writes;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('kashu_export_test');
      Hive.init(tempDir.path);
      if (!Hive.isAdapterRegistered(AssetTypeAdapter().typeId)) {
        Hive.registerAdapter(AssetTypeAdapter());
        Hive.registerAdapter(TransactionTypeAdapter());
        Hive.registerAdapter(AssetAdapter());
        Hive.registerAdapter(TransactionAdapter());
      }
      await Hive.openBox<Asset>(AppConstants.assetsBox);
      await Hive.openBox<Transaction>(AppConstants.transactionsBox);
      final settings = await Hive.openBox(AppConstants.settingsBox);
      assetRepo = AssetRepository();
      txRepo = TransactionRepository();
      writes = PortfolioWriteService(
        assetRepository: assetRepo,
        transactionRepository: txRepo,
        settingsBox: settings,
      );
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await tempDir.delete(recursive: true);
    });

    List<CapitalGainRow> gains() {
      final assets = assetRepo.getAllAssets();
      return ExportService.computeCapitalGains(
        assets,
        txRepo.getAllTransactions(),
        {for (final a in assets) a.id: a.name},
      );
    }

    test('appears in the capital-gains rows with the right figures',
        () async {
      // 10 @ 100 bought 1 Jan 2023, with its initial BUY logged.
      await writes.addAssetWithBuyTransaction(
          _asset(qty: 10, buy: 100, purchaseDate: DateTime(2023, 1, 1)));

      await writes.recordSell(
        assetId: 'a1',
        quantity: 4,
        pricePerUnit: 130,
        date: DateTime(2023, 6, 1),
      );

      final row = gains().single;
      expect(row.assetName, 'Reliance');
      expect(row.quantity, 4);
      expect(row.salePrice, 130);
      expect(row.saleProceeds, 520);
      expect(row.avgCostBasis, 100);
      expect(row.costBasis, 400);
      expect(row.gain, 120);
      expect(row.isLongTerm, isFalse); // 151 days
      expect(row.currency, 'INR');
    });

    test('a full exit keeps its row — the asset stays at quantity 0',
        () async {
      await writes.addAssetWithBuyTransaction(
          _asset(qty: 10, buy: 100, purchaseDate: DateTime(2023, 1, 1)));

      await writes.recordSell(
        assetId: 'a1',
        quantity: 10,
        pricePerUnit: 90,
        date: DateTime(2024, 2, 1),
      );

      expect(assetRepo.getAssetById('a1')!.quantity, 0);
      final row = gains().single;
      expect(row.gain, -100); // 900 proceeds - 1000 cost
      expect(row.isLongTerm, isTrue); // 396 days
    });

    test('dividends and interest never become gain rows', () async {
      await writes.addAssetWithBuyTransaction(_asset());
      await writes.recordIncome(
        assetId: 'a1',
        type: TransactionType.dividend,
        amount: 25,
        date: DateTime(2023, 6, 1),
      );

      expect(gains(), isEmpty);
    });
  });
}
