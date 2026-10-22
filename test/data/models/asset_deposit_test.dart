import 'package:flutter_test/flutter_test.dart';
import 'package:kashu/data/models/asset.dart';
import 'package:kashu/data/models/asset_type.dart';

DateTime _daysAgo(int days) {
  final d = DateTime.now().subtract(Duration(days: days));
  return DateTime(d.year, d.month, d.day);
}

Asset _deposit({
  required DateTime start,
  required DateTime maturity,
  double principal = 100000,
  double storedPrice = 100000,
  double quantity = 1,
  double? rate = 10,
  String? compounding = 'yearly',
  double? instalment,
  AssetType type = AssetType.fixedDeposit,
}) =>
    Asset(
      id: 'dep',
      name: 'Deposit',
      type: type,
      quantity: quantity,
      purchasePrice: principal,
      currentPrice: storedPrice,
      currency: 'INR',
      purchaseDate: start,
      createdAt: start,
      updatedAt: start,
      depositRatePercent: rate,
      depositMaturityDate: maturity,
      depositCompounding: instalment == null ? compounding : null,
      rdMonthlyInstalment: instalment,
    );

void main() {
  group('a fixed deposit with terms', () {
    test('is worth more today than on the day it was saved', () {
      final fd = _deposit(
        start: _daysAgo(365),
        maturity: _daysAgo(-365),
        storedPrice: 100000, // frozen on the day it was added
      );
      expect(fd.hasDepositSchedule, isTrue);
      // 10% compounded yearly for a year — without any price refresh.
      expect(fd.currentValue, closeTo(110000, 30));
      expect(fd.effectiveCurrentPrice, fd.currentValue);
      expect(fd.totalInvested, 100000);
      expect(fd.gainLoss, closeTo(10000, 30));
    });

    test('grows from one day to the next', () {
      final fd = _deposit(start: DateTime(2024, 1, 1),
          maturity: DateTime(2029, 1, 1));
      final monday = fd.currentPriceOn(DateTime(2025, 6, 2));
      final tuesday = fd.currentPriceOn(DateTime(2025, 6, 3));
      expect(tuesday, greaterThan(monday));
    });

    test('stops growing at maturity', () {
      final fd = _deposit(
          start: DateTime(2020, 1, 1), maturity: DateTime(2022, 1, 1));
      final atMaturity = fd.currentPriceOn(DateTime(2022, 1, 1));
      expect(atMaturity, closeTo(121000, 100)); // 1.1² (731 days)
      expect(fd.currentPriceOn(DateTime(2023, 5, 1)), atMaturity);
      expect(fd.currentValue, atMaturity); // today, long after maturity
    });

    test('scales with the quantity held', () {
      final two = _deposit(
          start: DateTime(2020, 1, 1),
          maturity: DateTime(2022, 1, 1),
          quantity: 2);
      expect(two.currentValue, closeTo(2 * 121000, 200));
    });
  });

  group('a recurring deposit with terms', () {
    test('started this month is worth its first instalment, not 0', () {
      final today = _daysAgo(0);
      final rd = _deposit(
        start: today,
        maturity: DateTime(today.year + 1, today.month, today.day),
        principal: 5000,
        storedPrice: 5000,
        rate: 7,
        instalment: 5000,
      );
      expect(rd.totalInvested, 5000);
      expect(rd.currentValue, 5000);
    });

    test('invests and grows month by month', () {
      final rd = _deposit(
        start: DateTime(2024, 1, 10),
        maturity: DateTime(2025, 1, 10),
        principal: 5000, // paid in when it was added
        storedPrice: 5000,
        rate: 7,
        instalment: 5000,
      );
      expect(rd.investedPriceOn(DateTime(2024, 6, 10)), 30000);
      expect(rd.currentPriceOn(DateTime(2024, 6, 10)), greaterThan(30000));
      // Matured long ago: all twelve instalments with their interest.
      expect(rd.totalInvested, 60000);
      // R × [(1+i)^12 − 1] / i × (1+i), i = 7%/12
      expect(rd.currentValue, closeTo(62324.38, 0.01));
    });
  });

  group('a deposit without complete terms is valued by hand', () {
    test('no terms at all (saved before schema v2)', () {
      final legacy = _deposit(
        start: DateTime(2023, 1, 1),
        maturity: DateTime(2026, 1, 1),
        rate: null,
        storedPrice: 104500,
      )..depositMaturityDate = null;
      expect(legacy.hasDepositSchedule, isFalse);
      expect(legacy.currentValue, 104500);
      expect(legacy.totalInvested, 100000);
    });

    test('an unknown compounding name', () {
      final odd = _deposit(
        start: DateTime(2023, 1, 1),
        maturity: DateTime(2026, 1, 1),
        compounding: 'weekly',
        storedPrice: 101000,
      );
      expect(odd.hasDepositSchedule, isFalse);
      expect(odd.currentValue, 101000);
    });

    test('terms on a holding that is not a deposit are ignored', () {
      final stock = _deposit(
        start: DateTime(2023, 1, 1),
        maturity: DateTime(2026, 1, 1),
        type: AssetType.stock,
        storedPrice: 90000,
      );
      expect(stock.hasDepositSchedule, isFalse);
      expect(stock.currentValue, 90000);
    });
  });

  group('the terms are kept', () {
    test('by copyWith, which every price update goes through', () {
      final fd = _deposit(
          start: DateTime(2024, 1, 1), maturity: DateTime(2027, 1, 1));
      final updated = fd.copyWith(currentPrice: 1, updatedAt: DateTime.now());
      expect(updated.depositRatePercent, 10);
      expect(updated.depositMaturityDate, DateTime(2027, 1, 1));
      expect(updated.depositCompounding, 'yearly');
      expect(updated.hasDepositSchedule, isTrue);
    });

    test('by toJson / fromJson', () {
      final rd = _deposit(
        start: DateTime(2024, 1, 10),
        maturity: DateTime(2025, 1, 10),
        rate: 7,
        instalment: 5000,
      );
      final json = rd.toJson();
      expect(json['rdMonthlyInstalment'], 5000);
      expect(json['depositCompounding'], isNull);

      final back = Asset.fromJson(json);
      expect(back.toJson(), json);
      expect(back.currentValue, rd.currentValue);
    });

    test('fromJson of a pre-v3 asset leaves them null', () {
      final json = _deposit(
          start: DateTime(2024, 1, 1), maturity: DateTime(2025, 1, 1))
          .toJson()
        ..remove('depositRatePercent')
        ..remove('depositMaturityDate')
        ..remove('depositCompounding')
        ..remove('rdMonthlyInstalment');
      final asset = Asset.fromJson(json);
      expect(asset.depositRatePercent, isNull);
      expect(asset.hasDepositSchedule, isFalse);
    });
  });
}
