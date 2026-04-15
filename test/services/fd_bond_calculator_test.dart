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
      // A = P(1 + r*t) = 100000 * 1.10 = 110000
      expect(result.maturityValue, closeTo(110000, 10.0));
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
}
