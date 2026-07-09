import 'package:flutter_test/flutter_test.dart';

import 'package:kashu/data/models/asset.dart';
import 'package:kashu/data/models/asset_type.dart';
import 'package:kashu/data/models/transaction.dart';
import 'package:kashu/data/models/transaction_type.dart';
import 'package:kashu/services/export_service.dart';

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

    test('null symbol/platform render as empty strings', () {
      final rows =
          ExportService.holdingsCsvRows([_asset(symbol: null, platform: null)]);
      expect(rows[1][1], ''); // Symbol
      expect(rows[1][3], ''); // Platform
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
}
