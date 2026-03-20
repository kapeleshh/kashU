import 'dart:math' as math;

/// Compounding frequency options for FD/Bond interest calculation.
enum CompoundingFrequency {
  monthly,
  quarterly,
  halfYearly,
  yearly,
  simple; // Simple interest (no compounding)

  String get label {
    switch (this) {
      case CompoundingFrequency.monthly:
        return 'Monthly';
      case CompoundingFrequency.quarterly:
        return 'Quarterly';
      case CompoundingFrequency.halfYearly:
        return 'Half-Yearly';
      case CompoundingFrequency.yearly:
        return 'Yearly';
      case CompoundingFrequency.simple:
        return 'Simple Interest';
    }
  }

  /// Number of compounding periods per year
  int get periodsPerYear {
    switch (this) {
      case CompoundingFrequency.monthly:
        return 12;
      case CompoundingFrequency.quarterly:
        return 4;
      case CompoundingFrequency.halfYearly:
        return 2;
      case CompoundingFrequency.yearly:
        return 1;
      case CompoundingFrequency.simple:
        return 1;
    }
  }
}

/// Result of an FD/Bond value calculation.
class FdBondCalculationResult {
  /// Original principal / face value
  final double principal;

  /// Annual interest rate (e.g. 7.5 for 7.5%)
  final double annualRatePercent;

  /// Start date of the FD/Bond
  final DateTime startDate;

  /// Maturity date
  final DateTime maturityDate;

  /// Compounding frequency
  final CompoundingFrequency compounding;

  /// Current value as of today
  final double currentValue;

  /// Value at maturity
  final double maturityValue;

  /// Total interest earned so far
  double get interestEarnedSoFar => currentValue - principal;

  /// Total interest at maturity
  double get totalInterestAtMaturity => maturityValue - principal;

  /// Days elapsed since start
  int get daysElapsed {
    final elapsed = DateTime.now().difference(startDate).inDays;
    return elapsed.clamp(0, totalDays);
  }

  /// Total tenure in days
  int get totalDays => maturityDate.difference(startDate).inDays;

  /// Progress percentage (0–100)
  double get progressPercent =>
      totalDays > 0 ? (daysElapsed / totalDays * 100).clamp(0.0, 100.0) : 0;

  /// Whether the FD/Bond has matured
  bool get isMatured => DateTime.now().isAfter(maturityDate);

  /// Days remaining to maturity (0 if already matured)
  int get daysRemaining {
    final remaining = maturityDate.difference(DateTime.now()).inDays;
    return remaining.clamp(0, totalDays);
  }

  const FdBondCalculationResult({
    required this.principal,
    required this.annualRatePercent,
    required this.startDate,
    required this.maturityDate,
    required this.compounding,
    required this.currentValue,
    required this.maturityValue,
  });
}

/// Calculates the current and maturity value of Fixed Deposits and Bonds
/// using compound interest (or simple interest) formula.
///
/// Formula (Compound Interest):
///   A = P × (1 + r/n)^(n×t)
///   where:
///     P = principal
///     r = annual rate (decimal)
///     n = compounding periods per year
///     t = time in years
///
/// Formula (Simple Interest):
///   A = P × (1 + r×t)
class FdBondCalculator {
  /// Calculate the current and maturity value of an FD/Bond.
  ///
  /// [principal] — invested amount in INR
  /// [annualRatePercent] — interest rate per year (e.g. 7.5 for 7.5%)
  /// [startDate] — when the FD/Bond started
  /// [maturityDate] — when it matures
  /// [compounding] — how often interest is compounded
  static FdBondCalculationResult calculate({
    required double principal,
    required double annualRatePercent,
    required DateTime startDate,
    required DateTime maturityDate,
    required CompoundingFrequency compounding,
  }) {
    final r = annualRatePercent / 100.0;
    final now = DateTime.now();

    // Cap "now" at maturity so we don't show more than maturity value
    final effectiveNow = now.isAfter(maturityDate) ? maturityDate : now;
    final elapsedDays = effectiveNow.difference(startDate).inDays;
    final totalDays = maturityDate.difference(startDate).inDays;

    // Time in years
    final tNow = elapsedDays / 365.0;
    final tTotal = totalDays / 365.0;

    double currentValue;
    double maturityValue;

    if (compounding == CompoundingFrequency.simple) {
      // Simple interest: A = P(1 + r×t)
      currentValue = principal * (1.0 + r * tNow);
      maturityValue = principal * (1.0 + r * tTotal);
    } else {
      // Compound interest: A = P × (1 + r/n)^(n×t)
      final n = compounding.periodsPerYear.toDouble();
      currentValue = principal * math.pow(1.0 + r / n, n * tNow).toDouble();
      maturityValue = principal * math.pow(1.0 + r / n, n * tTotal).toDouble();
    }

    // Ensure values are never less than principal (edge case: negative rates)
    currentValue = math.max(currentValue, principal);
    maturityValue = math.max(maturityValue, principal);

    return FdBondCalculationResult(
      principal: principal,
      annualRatePercent: annualRatePercent,
      startDate: startDate,
      maturityDate: maturityDate,
      compounding: compounding,
      currentValue: currentValue,
      maturityValue: maturityValue,
    );
  }

  /// Quick helper: calculate maturity value given tenure in months.
  static double calculateMaturityValue({
    required double principal,
    required double annualRatePercent,
    required int tenureMonths,
    CompoundingFrequency compounding = CompoundingFrequency.quarterly,
  }) {
    final startDate = DateTime.now();
    final maturityDate = DateTime(
      startDate.year,
      startDate.month + tenureMonths,
      startDate.day,
    );
    return calculate(
      principal: principal,
      annualRatePercent: annualRatePercent,
      startDate: startDate,
      maturityDate: maturityDate,
      compounding: compounding,
    ).maturityValue;
  }
}
