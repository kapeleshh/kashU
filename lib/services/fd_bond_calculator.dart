import 'dart:math' as math;

/// Compounding frequency options for FD/Bond interest calculation.
enum CompoundingFrequency {
  monthly,
  quarterly,
  halfYearly,
  yearly,
  simple; // Simple interest (no compounding)

  /// The frequency stored under [name] (what an Asset keeps on disk and in
  /// backups), or null for anything else.
  static CompoundingFrequency? fromName(String? name) =>
      name == null ? null : values.asNameMap()[name];

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
  /// [asOf] — the day to value it on (default today). Counted in whole
  /// calendar days, and capped at maturity: a matured deposit stops growing.
  static FdBondCalculationResult calculate({
    required double principal,
    required double annualRatePercent,
    required DateTime startDate,
    required DateTime maturityDate,
    required CompoundingFrequency compounding,
    DateTime? asOf,
  }) {
    final r = annualRatePercent / 100.0;
    final start = _day(startDate);
    final maturity = _day(maturityDate);

    // Cap "now" at maturity so we don't show more than maturity value
    var today = _day(asOf ?? DateTime.now());
    if (today.isAfter(maturity)) today = maturity;
    final elapsedDays = math.max(0, today.difference(start).inDays);
    final totalDays = math.max(0, maturity.difference(start).inDays);

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

  /// Value a recurring deposit: [monthlyInstalment] paid on the start date
  /// and on the same day of every month after it, while that day is still
  /// before maturity, compounding monthly.
  ///
  /// An instalment is counted as paid from its due date, so an RD started
  /// today already holds its first instalment — it is never worth 0. Each
  /// paid instalment grows by (1 + r/12) per month for the fractional months
  /// since it was paid, so the value moves every day and, for a tenure of
  /// whole months, lands exactly on the standard maturity formula
  /// M = R × [(1+i)^n − 1] / i × (1+i). [asOf] (default today) is capped at
  /// maturity.
  static RecurringDepositResult calculateRecurring({
    required double monthlyInstalment,
    required double annualRatePercent,
    required DateTime startDate,
    required DateTime maturityDate,
    DateTime? asOf,
  }) {
    final start = _day(startDate);
    final maturity = _day(maturityDate);
    final total = rdInstalmentCount(start, maturity);
    final monthlyRate = annualRatePercent / 100.0 / 12.0;

    double valueOn(DateTime day, int paid) {
      if (paid <= 0) return 0;
      final t = fractionalMonthsBetween(start, day);
      var value = 0.0;
      for (var j = 0; j < paid; j++) {
        value += monthlyInstalment *
            math.pow(1.0 + monthlyRate, math.max(0.0, t - j)).toDouble();
      }
      return value;
    }

    var today = _day(asOf ?? DateTime.now());
    if (today.isAfter(maturity)) today = maturity;
    final paid = today.isBefore(start)
        ? 0
        : math.min(total, monthsBetween(start, today) + 1);

    final invested = monthlyInstalment * paid;
    // Never below what was paid in (a 0 or negative rate).
    final current = math.max(valueOn(today, paid), invested);
    final atMaturity =
        math.max(valueOn(maturity, total), monthlyInstalment * total);

    return RecurringDepositResult(
      instalmentsPaid: paid,
      totalInstalments: total,
      investedSoFar: invested,
      totalToInvest: monthlyInstalment * total,
      currentValue: math.min(current, atMaturity),
      maturityValue: atMaturity,
    );
  }

  /// How many instalments a recurring deposit from [start] to [maturity]
  /// takes: one on the start date and one a month after each, while the
  /// due date is still before maturity. 12 for a one-year RD.
  static int rdInstalmentCount(DateTime start, DateTime maturity) {
    final from = _day(start);
    final to = _day(maturity);
    if (!to.isAfter(from)) return 0;
    final whole = monthsBetween(from, to);
    // The instalment due on a whole-month anniversary that falls before
    // maturity is still paid.
    return addMonths(from, whole).isBefore(to) ? whole + 1 : whole;
  }

  /// Whole calendar months from [from] to [to] (0 when [to] is earlier).
  /// A month ends on the same day of the next month, or on its last day
  /// when it is shorter: 31 Jan → 28 Feb is one month.
  static int monthsBetween(DateTime from, DateTime to) {
    final a = _day(from);
    final b = _day(to);
    if (b.isBefore(a)) return 0;
    var months = (b.year - a.year) * 12 + (b.month - a.month);
    if (addMonths(a, months).isAfter(b)) months--;
    return math.max(0, months);
  }

  /// [monthsBetween] plus the elapsed share of the month in progress, by
  /// day, so a deposit's value moves daily between monthly anniversaries.
  static double fractionalMonthsBetween(DateTime from, DateTime to) {
    final a = _day(from);
    final b = _day(to);
    if (!b.isAfter(a)) return 0;
    final whole = monthsBetween(a, b);
    final anchor = addMonths(a, whole);
    final next = addMonths(a, whole + 1);
    return whole +
        b.difference(anchor).inDays / next.difference(anchor).inDays;
  }

  /// [date] moved by [months] calendar months, the day clamped to the
  /// length of the target month (31 Jan + 1 month = 28/29 Feb). Returns a
  /// UTC calendar day.
  static DateTime addMonths(DateTime date, int months) {
    final monthIndex = date.month - 1 + months;
    final year = date.year + (monthIndex / 12).floor();
    final month = monthIndex % 12 + 1; // Dart's % is never negative
    final lastDay = DateTime.utc(year, month + 1, 0).day;
    return DateTime.utc(year, month, math.min(date.day, lastDay));
  }

  /// The calendar day of [d], as a UTC midnight so that day counts are
  /// never thrown off by a daylight-saving shift.
  static DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);
}

/// A recurring deposit valued on one day by
/// [FdBondCalculator.calculateRecurring].
class RecurringDepositResult {
  /// Instalments due by the valuation day (the first is due on the start
  /// date).
  final int instalmentsPaid;

  /// Instalments over the whole tenure.
  final int totalInstalments;

  /// [instalmentsPaid] × the instalment.
  final double investedSoFar;

  /// [totalInstalments] × the instalment.
  final double totalToInvest;

  /// What the paid instalments are worth with interest on the valuation
  /// day, capped at [maturityValue].
  final double currentValue;

  /// What the deposit pays out at maturity.
  final double maturityValue;

  const RecurringDepositResult({
    required this.instalmentsPaid,
    required this.totalInstalments,
    required this.investedSoFar,
    required this.totalToInvest,
    required this.currentValue,
    required this.maturityValue,
  });
}

/// The terms of a fixed or recurring deposit — everything needed to value it
/// on any day without a network refresh. An Asset stores these (rate,
/// maturity date, compounding or monthly instalment, with its purchase date
/// as the start and its purchase price as an FD's principal) and builds one
/// through `Asset.depositSchedule`; the deposit calculator builds one from
/// what the user typed.
class DepositSchedule {
  /// Rates above this are refused by the calculator and by imports: a typo
  /// (75 for 7.5), not a deposit.
  static const double maxRatePercent = 100;

  /// The day the deposit was opened (an RD's first instalment).
  final DateTime startDate;

  final DateTime maturityDate;

  /// Annual interest rate, e.g. 7.5 for 7.5% p.a.
  final double annualRatePercent;

  /// A fixed deposit's principal, per unit held. Unused for an RD.
  final double principal;

  /// How a fixed deposit compounds. An RD compounds monthly.
  final CompoundingFrequency compounding;

  /// A recurring deposit's monthly instalment; null for a fixed deposit.
  final double? monthlyInstalment;

  const DepositSchedule({
    required this.startDate,
    required this.maturityDate,
    required this.annualRatePercent,
    required this.principal,
    required this.compounding,
    this.monthlyInstalment,
  });

  bool get isRecurring => monthlyInstalment != null;

  /// Worth on [day] (per unit held), growing daily and capped at maturity.
  double valueAsOf(DateTime day) => isRecurring
      ? _recurring(day).currentValue
      : FdBondCalculator.calculate(
          principal: principal,
          annualRatePercent: annualRatePercent,
          startDate: startDate,
          maturityDate: maturityDate,
          compounding: compounding,
          asOf: day,
        ).currentValue;

  /// Paid in by [day] (per unit held): an FD's principal, or an RD's
  /// instalments due so far.
  double investedAsOf(DateTime day) =>
      isRecurring ? _recurring(day).investedSoFar : principal;

  /// What it pays out at maturity (per unit held).
  double get maturityValue => valueAsOf(maturityDate);

  /// Whether [day] is on or after the maturity date.
  bool isMaturedOn(DateTime day) => !FdBondCalculator._day(day)
      .isBefore(FdBondCalculator._day(maturityDate));

  RecurringDepositResult _recurring(DateTime day) =>
      FdBondCalculator.calculateRecurring(
        monthlyInstalment: monthlyInstalment!,
        annualRatePercent: annualRatePercent,
        startDate: startDate,
        maturityDate: maturityDate,
        asOf: day,
      );
}
