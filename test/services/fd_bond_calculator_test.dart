import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kashu/services/fd_bond_calculator.dart';

void main() {
  group('CompoundingFrequency', () {
    test('periodsPerYear values are correct', () {
      expect(CompoundingFrequency.monthly.periodsPerYear, 12);
      expect(CompoundingFrequency.quarterly.periodsPerYear, 4);
      expect(CompoundingFrequency.halfYearly.periodsPerYear, 2);
      expect(CompoundingFrequency.yearly.periodsPerYear, 1);
      expect(CompoundingFrequency.simple.periodsPerYear, 1);
    });

    test('labels are non-empty', () {
      for (final freq in CompoundingFrequency.values) {
        expect(freq.label.isNotEmpty, true,
            reason: '${freq.name}.label should not be empty');
      }
    });
  });

  group('FdBondCalculator.calculate — simple interest', () {
    test('principal at day 0 equals principal', () {
      final now = DateTime.now();
      final result = FdBondCalculator.calculate(
        principal: 100000,
        annualRatePercent: 7.0,
        startDate: now,
        maturityDate: now.add(const Duration(days: 365)),
        compounding: CompoundingFrequency.simple,
      );
      // No time elapsed → current value ≈ principal
      expect(result.currentValue, closeTo(100000, 1.0));
    });

    test('maturity value is correct for 1-year simple interest at 10%', () {
      final start = DateTime(2024, 1, 1);
      final maturity = DateTime(2025, 1, 1);
      final result = FdBondCalculator.calculate(
        principal: 100000,
        annualRatePercent: 10.0,
        startDate: start,
        maturityDate: maturity,
        compounding: CompoundingFrequency.simple,
      );
      // A = P(1 + r*t) where t = actual days / 365; 2024 is a leap year (366 days)
      // so maturity ≈ 100000 * (1 + 0.10 * 366/365) ≈ 110027
      expect(result.maturityValue, closeTo(110000, 50.0));
    });

    test('maturity value is correct for 2-year simple interest at 8%', () {
      final start = DateTime(2023, 1, 1);
      final maturity = DateTime(2025, 1, 1);
      final result = FdBondCalculator.calculate(
        principal: 50000,
        annualRatePercent: 8.0,
        startDate: start,
        maturityDate: maturity,
        compounding: CompoundingFrequency.simple,
      );
      // A = 50000 * (1 + 0.08 * 2) = 50000 * 1.16 = 58000
      expect(result.maturityValue, closeTo(58000, 50.0));
    });
  });

  group('FdBondCalculator.calculate — compound interest', () {
    test('quarterly compounding at 7.5% for 1 year', () {
      final start = DateTime(2024, 1, 1);
      final maturity = DateTime(2025, 1, 1);
      final result = FdBondCalculator.calculate(
        principal: 100000,
        annualRatePercent: 7.5,
        startDate: start,
        maturityDate: maturity,
        compounding: CompoundingFrequency.quarterly,
      );
      // A = 100000 * (1 + 0.075/4)^4 ≈ 107714
      expect(result.maturityValue, closeTo(107714, 50.0));
    });

    test('monthly compounding at 6% for 1 year', () {
      final start = DateTime(2024, 1, 1);
      final maturity = DateTime(2025, 1, 1);
      final result = FdBondCalculator.calculate(
        principal: 100000,
        annualRatePercent: 6.0,
        startDate: start,
        maturityDate: maturity,
        compounding: CompoundingFrequency.monthly,
      );
      // A = 100000 * (1 + 0.06/12)^12 ≈ 106168
      expect(result.maturityValue, closeTo(106168, 50.0));
    });

    test('yearly compounding at 8% for 3 years', () {
      final start = DateTime(2022, 1, 1);
      final maturity = DateTime(2025, 1, 1);
      final result = FdBondCalculator.calculate(
        principal: 100000,
        annualRatePercent: 8.0,
        startDate: start,
        maturityDate: maturity,
        compounding: CompoundingFrequency.yearly,
      );
      // A = 100000 * (1.08)^3 ≈ 125971
      expect(result.maturityValue, closeTo(125971, 100.0));
    });

    test('half-yearly compounding at 7% for 1 year', () {
      final start = DateTime(2024, 1, 1);
      final maturity = DateTime(2025, 1, 1);
      final result = FdBondCalculator.calculate(
        principal: 100000,
        annualRatePercent: 7.0,
        startDate: start,
        maturityDate: maturity,
        compounding: CompoundingFrequency.halfYearly,
      );
      // A = 100000 * (1 + 0.07/2)^2 ≈ 107123
      expect(result.maturityValue, closeTo(107123, 50.0));
    });

    test('maturity value is always >= principal', () {
      final start = DateTime(2024, 1, 1);
      final maturity = DateTime(2025, 1, 1);
      final result = FdBondCalculator.calculate(
        principal: 200000,
        annualRatePercent: 0.0,
        startDate: start,
        maturityDate: maturity,
        compounding: CompoundingFrequency.quarterly,
      );
      expect(result.maturityValue, greaterThanOrEqualTo(result.principal));
    });
  });

  group('FdBondCalculationResult — computed properties', () {
    late FdBondCalculationResult result;

    setUp(() {
      final start = DateTime(2024, 1, 1);
      final maturity = DateTime(2025, 1, 1);
      result = FdBondCalculator.calculate(
        principal: 100000,
        annualRatePercent: 7.5,
        startDate: start,
        maturityDate: maturity,
        compounding: CompoundingFrequency.quarterly,
      );
    });

    test('totalDays is 365 for 2024 (leap year)', () {
      expect(result.totalDays, 366); // 2024 is a leap year
    });

    test('progressPercent is between 0 and 100', () {
      expect(result.progressPercent, greaterThanOrEqualTo(0));
      expect(result.progressPercent, lessThanOrEqualTo(100));
    });

    test('interestEarnedSoFar is non-negative', () {
      expect(result.interestEarnedSoFar, greaterThanOrEqualTo(0));
    });

    test('totalInterestAtMaturity > 0 for positive rate', () {
      expect(result.totalInterestAtMaturity, greaterThan(0));
    });

    test('daysRemaining is 0 for already-matured FD', () {
      final pastStart = DateTime(2020, 1, 1);
      final pastMaturity = DateTime(2021, 1, 1);
      final maturedResult = FdBondCalculator.calculate(
        principal: 100000,
        annualRatePercent: 7.0,
        startDate: pastStart,
        maturityDate: pastMaturity,
        compounding: CompoundingFrequency.quarterly,
      );
      expect(maturedResult.isMatured, true);
      expect(maturedResult.daysRemaining, 0);
    });

    test('daysElapsed is clamped to totalDays when matured', () {
      final pastStart = DateTime(2020, 1, 1);
      final pastMaturity = DateTime(2021, 1, 1);
      final maturedResult = FdBondCalculator.calculate(
        principal: 100000,
        annualRatePercent: 7.0,
        startDate: pastStart,
        maturityDate: pastMaturity,
        compounding: CompoundingFrequency.quarterly,
      );
      expect(maturedResult.daysElapsed,
          lessThanOrEqualTo(maturedResult.totalDays));
    });

    test('current value does not exceed maturity value', () {
      expect(result.currentValue, lessThanOrEqualTo(result.maturityValue));
    });
  });

  group('FdBondCalculator.calculateMaturityValue — quick helper', () {
    test('12-month FD at 7% quarterly compounding', () {
      final maturity = FdBondCalculator.calculateMaturityValue(
        principal: 100000,
        annualRatePercent: 7.0,
        tenureMonths: 12,
        compounding: CompoundingFrequency.quarterly,
      );
      // A = 100000 * (1 + 0.07/4)^4 ≈ 107186
      expect(maturity, closeTo(107186, 100.0));
    });

    test('default compounding is quarterly', () {
      final withExplicit = FdBondCalculator.calculateMaturityValue(
        principal: 100000,
        annualRatePercent: 8.0,
        tenureMonths: 12,
        compounding: CompoundingFrequency.quarterly,
      );
      final withDefault = FdBondCalculator.calculateMaturityValue(
        principal: 100000,
        annualRatePercent: 8.0,
        tenureMonths: 12,
      );
      expect(withDefault, closeTo(withExplicit, 0.01));
    });

    test('longer tenure produces larger maturity value', () {
      final short = FdBondCalculator.calculateMaturityValue(
        principal: 100000,
        annualRatePercent: 7.0,
        tenureMonths: 12,
      );
      final long = FdBondCalculator.calculateMaturityValue(
        principal: 100000,
        annualRatePercent: 7.0,
        tenureMonths: 24,
      );
      expect(long, greaterThan(short));
    });
  });

  group('FdBondCalculator.calculate — asOf (daily growth)', () {
    final start = DateTime(2024, 1, 1);
    final maturity = DateTime(2027, 1, 1);
    double valueOn(DateTime day) => FdBondCalculator.calculate(
          principal: 100000,
          annualRatePercent: 7.5,
          startDate: start,
          maturityDate: maturity,
          compounding: CompoundingFrequency.quarterly,
          asOf: day,
        ).currentValue;

    test('is the principal on the start day and grows every day after', () {
      expect(valueOn(start), 100000);
      final dayOne = valueOn(DateTime(2024, 1, 2));
      expect(dayOne, greaterThan(100000));
      expect(valueOn(DateTime(2024, 1, 3)), greaterThan(dayOne));
      expect(valueOn(DateTime(2025, 1, 1)), closeTo(107735, 5)); // 366 days
    });

    test('stops at the maturity value', () {
      final atMaturity = valueOn(maturity);
      expect(valueOn(DateTime(2030, 6, 1)), atMaturity);
      // 1096 days (2024 is a leap year) at 7.5% compounded quarterly.
      expect(atMaturity, closeTo(124997, 5));
    });

    test('ignores the time of day', () {
      expect(valueOn(DateTime(2024, 6, 1, 23, 59)),
          valueOn(DateTime(2024, 6, 1)));
    });
  });

  group('calendar months', () {
    test('monthsBetween counts whole calendar months', () {
      expect(FdBondCalculator.monthsBetween(
          DateTime(2024, 1, 15), DateTime(2024, 2, 14)), 0);
      expect(FdBondCalculator.monthsBetween(
          DateTime(2024, 1, 15), DateTime(2024, 2, 15)), 1);
      expect(FdBondCalculator.monthsBetween(
          DateTime(2024, 1, 15), DateTime(2034, 1, 15)), 120);
      // A month from the 31st ends on the last day of a shorter month.
      expect(FdBondCalculator.monthsBetween(
          DateTime(2025, 1, 31), DateTime(2025, 2, 28)), 1);
    });

    test('addMonths clamps to the end of the month', () {
      expect(FdBondCalculator.addMonths(DateTime(2024, 1, 31), 1),
          DateTime.utc(2024, 2, 29));
      expect(FdBondCalculator.addMonths(DateTime(2024, 11, 30), 3),
          DateTime.utc(2025, 2, 28));
    });

    test('rdInstalmentCount: 12 for a one-year RD', () {
      expect(FdBondCalculator.rdInstalmentCount(
          DateTime(2024, 3, 10), DateTime(2025, 3, 10)), 12);
      // An odd maturity still collects the instalment due before it.
      expect(FdBondCalculator.rdInstalmentCount(
          DateTime(2024, 3, 10), DateTime(2025, 3, 20)), 13);
      expect(FdBondCalculator.rdInstalmentCount(
          DateTime(2024, 3, 10), DateTime(2024, 3, 10)), 0);
    });
  });

  group('FdBondCalculator.calculateRecurring', () {
    final start = DateTime(2024, 1, 10);
    final maturity = DateTime(2025, 1, 10);
    RecurringDepositResult on(DateTime day) =>
        FdBondCalculator.calculateRecurring(
          monthlyInstalment: 5000,
          annualRatePercent: 7.0,
          startDate: start,
          maturityDate: maturity,
          asOf: day,
        );

    test('an RD started today already holds its first instalment', () {
      final today = on(start);
      expect(today.instalmentsPaid, 1);
      expect(today.investedSoFar, 5000);
      expect(today.currentValue, 5000);
    });

    test('a new instalment is counted on each monthly due date', () {
      expect(on(DateTime(2024, 2, 9)).instalmentsPaid, 1);
      expect(on(DateTime(2024, 2, 10)).instalmentsPaid, 2);
      expect(on(DateTime(2024, 12, 31)).instalmentsPaid, 12);
    });

    test('matches the standard RD maturity formula', () {
      // M = R × [(1+i)^n − 1] / i × (1+i), i = 7%/12, n = 12
      const i = 0.07 / 12;
      final expected = 5000 * (math.pow(1 + i, 12) - 1) / i * (1 + i);
      expect(on(maturity).maturityValue, closeTo(expected, 0.01));
      expect(on(maturity).currentValue, closeTo(expected, 0.01));
      expect(on(maturity).totalToInvest, 60000);
    });

    test('grows between instalments and stops at maturity', () {
      final early = on(DateTime(2024, 3, 1)).currentValue;
      final later = on(DateTime(2024, 3, 5)).currentValue;
      expect(later, greaterThan(early));
      expect(on(DateTime(2026, 1, 1)).currentValue,
          on(maturity).maturityValue);
      expect(on(DateTime(2026, 1, 1)).investedSoFar, 60000);
    });
  });

  group('DepositSchedule', () {
    test('values an FD from its principal', () {
      final fd = DepositSchedule(
        startDate: DateTime(2024, 1, 1),
        maturityDate: DateTime(2025, 1, 1),
        annualRatePercent: 7.5,
        principal: 100000,
        compounding: CompoundingFrequency.quarterly,
      );
      expect(fd.isRecurring, isFalse);
      expect(fd.investedAsOf(DateTime(2024, 6, 1)), 100000);
      expect(fd.valueAsOf(DateTime(2024, 1, 1)), 100000);
      expect(fd.maturityValue, closeTo(107714, 50));
      expect(fd.isMaturedOn(DateTime(2024, 12, 31)), isFalse);
      expect(fd.isMaturedOn(DateTime(2025, 1, 1)), isTrue);
    });

    test('values an RD from its instalments', () {
      final rd = DepositSchedule(
        startDate: DateTime(2024, 1, 10),
        maturityDate: DateTime(2025, 1, 10),
        annualRatePercent: 7.0,
        principal: 0, // unused for an RD
        compounding: CompoundingFrequency.monthly,
        monthlyInstalment: 5000,
      );
      expect(rd.isRecurring, isTrue);
      expect(rd.investedAsOf(DateTime(2024, 1, 10)), 5000);
      expect(rd.investedAsOf(DateTime(2024, 4, 10)), 20000);
      expect(rd.valueAsOf(DateTime(2024, 4, 10)), greaterThan(20000));
    });

    test('CompoundingFrequency.fromName reads stored names only', () {
      expect(CompoundingFrequency.fromName('halfYearly'),
          CompoundingFrequency.halfYearly);
      expect(CompoundingFrequency.fromName('weekly'), isNull);
      expect(CompoundingFrequency.fromName(null), isNull);
    });
  });
}
