import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/utils/amount_validator.dart';
import '../../core/utils/currency_formatter.dart';
import '../../services/fd_bond_calculator.dart';

/// Deposit sub-type: Fixed Deposit or Recurring Deposit
enum DepositType { fixed, recurring }

/// Input mode: user knows the interest rate, or knows the maturity amount
enum DepositInputMode { byRate, byMaturity }

/// Result passed back to the parent when the user fills in deposit details.
class FdBondInputResult {
  /// An FD's principal, or what an RD has paid in so far (at least its
  /// first instalment once it has started).
  final double principal;
  final double annualRatePercent;
  final DateTime startDate;
  final DateTime maturityDate;
  final CompoundingFrequency compounding;
  final FdBondCalculationResult calculation;
  final DepositType depositType;
  final double? monthlyInstallment; // for RD

  /// An RD's instalments over the whole tenure; null for an FD.
  final double? totalToInvest;

  const FdBondInputResult({
    required this.principal,
    required this.annualRatePercent,
    required this.startDate,
    required this.maturityDate,
    required this.compounding,
    required this.calculation,
    required this.depositType,
    this.monthlyInstallment,
    this.totalToInvest,
  });

  /// The terms to store with the holding, so its value keeps growing after
  /// the day it was added.
  DepositSchedule get schedule => DepositSchedule(
        startDate: startDate,
        maturityDate: maturityDate,
        annualRatePercent: annualRatePercent,
        principal: principal,
        compounding: compounding,
        monthlyInstalment:
            depositType == DepositType.recurring ? monthlyInstallment : null,
      );
}

/// Smart input widget for Fixed Deposits, Recurring Deposits, and Bonds.
///
/// Features:
/// - FD / RD toggle (for deposits)
/// - Two input modes: by interest rate OR by maturity amount
/// - Live compound interest calculation
/// - Progress bar, maturity tracking, Cr/L/K formatting
class FdBondInputField extends StatefulWidget {
  final bool isFd; // true = Deposit (FD/RD), false = Bond

  /// The currency the holding is being entered in — the amounts here are
  /// written straight into its purchase and current price.
  final String currency;

  /// Terms to start from, when editing a deposit that has them.
  final DepositSchedule? initial;

  /// Called with the deposit's details whenever they change, and with null
  /// whenever they stop adding up (a field cleared or out of range).
  final void Function(FdBondInputResult? result) onChanged;

  const FdBondInputField({
    super.key,
    required this.isFd,
    required this.currency,
    required this.onChanged,
    this.initial,
  });

  @override
  State<FdBondInputField> createState() => _FdBondInputFieldState();
}

class _FdBondInputFieldState extends State<FdBondInputField> {
  final _principalController = TextEditingController();
  final _rateController = TextEditingController();
  final _maturityAmountController = TextEditingController();
  final _monthlyInstallmentController = TextEditingController();

  DateTime _startDate = DateTime.now();
  DateTime _maturityDate = DateTime.now().add(const Duration(days: 365));
  CompoundingFrequency _compounding = CompoundingFrequency.quarterly;
  DepositType _depositType = DepositType.fixed;
  DepositInputMode _inputMode = DepositInputMode.byRate;

  /// The current calculation, or null while the inputs don't add up.
  FdBondInputResult? _input;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _startDate = initial.startDate;
      _maturityDate = initial.maturityDate;
      _rateController.text = _plain(initial.annualRatePercent);
      if (initial.isRecurring) {
        _depositType = DepositType.recurring;
        _monthlyInstallmentController.text =
            _plain(initial.monthlyInstalment!);
      } else {
        _compounding = initial.compounding;
        _principalController.text = _plain(initial.principal);
      }
      // Shown, not reported: the parent already holds these terms.
      _input = _compute();
    }
    _principalController.addListener(_recalculate);
    _rateController.addListener(_recalculate);
    _maturityAmountController.addListener(_recalculate);
    _monthlyInstallmentController.addListener(_recalculate);
  }

  @override
  void dispose() {
    _principalController.dispose();
    _rateController.dispose();
    _maturityAmountController.dispose();
    _monthlyInstallmentController.dispose();
    super.dispose();
  }

  /// 5000 rather than 5000.0, but 7.25 as typed.
  static String _plain(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();

  void _recalculate() {
    final input = _compute();
    setState(() => _input = input);
    widget.onChanged(input);
  }

  /// The deposit as currently entered, or null when it doesn't add up.
  FdBondInputResult? _compute() {
    if (!_maturityDate.isAfter(_startDate)) return null;
    if (_depositType == DepositType.recurring) return _computeRd();
    return _inputMode == DepositInputMode.byRate
        ? _computeFdByRate()
        : _computeFdByMaturity();
  }

  /// The typed rate when it is a usable one (above 0, at most 100% p.a.).
  double? _typedRate() {
    final rate = AmountValidator.parse(_rateController.text);
    if (rate == null || rate <= 0 || rate > DepositSchedule.maxRatePercent) {
      return null;
    }
    return rate;
  }

  double? _typedPrincipal() {
    final principal = AmountValidator.parse(_principalController.text);
    return principal == null || principal <= 0 ? null : principal;
  }

  FdBondInputResult? _computeFdByRate() {
    final principal = _typedPrincipal();
    final rate = _typedRate();
    if (principal == null || rate == null) return null;
    return _fdResult(principal, rate);
  }

  FdBondInputResult? _computeFdByMaturity() {
    final principal = _typedPrincipal();
    final maturityAmount =
        AmountValidator.parse(_maturityAmountController.text);
    if (principal == null ||
        maturityAmount == null ||
        maturityAmount <= principal) {
      return null;
    }

    // Back-calculate the annual interest rate from maturity amount
    final totalDays = DateUtils.dateOnly(_maturityDate)
        .difference(DateUtils.dateOnly(_startDate))
        .inDays;
    if (totalDays <= 0) return null;
    final tTotal = totalDays / 365.0;

    double derivedRate;
    if (_compounding == CompoundingFrequency.simple) {
      // A = P(1 + rt) → r = (A/P - 1) / t
      derivedRate = ((maturityAmount / principal) - 1) / tTotal * 100;
    } else {
      // A = P(1 + r/n)^(nt) → r = n × ((A/P)^(1/(nt)) - 1)
      final n = _compounding.periodsPerYear.toDouble();
      final ratio = maturityAmount / principal;
      final exponent = 1.0 / (n * tTotal);
      derivedRate = n * (math.pow(ratio, exponent).toDouble() - 1) * 100;
    }

    if (!derivedRate.isFinite ||
        derivedRate <= 0 ||
        derivedRate > DepositSchedule.maxRatePercent) {
      return null;
    }
    return _fdResult(principal, derivedRate);
  }

  FdBondInputResult _fdResult(double principal, double rate) {
    final calculation = FdBondCalculator.calculate(
      principal: principal,
      annualRatePercent: rate,
      startDate: _startDate,
      maturityDate: _maturityDate,
      compounding: _compounding,
    );
    return FdBondInputResult(
      principal: principal,
      annualRatePercent: rate,
      startDate: _startDate,
      maturityDate: _maturityDate,
      compounding: _compounding,
      calculation: calculation,
      depositType: _depositType,
    );
  }

  FdBondInputResult? _computeRd() {
    final installment =
        AmountValidator.parse(_monthlyInstallmentController.text);
    if (installment == null || installment <= 0) return null;
    final instalments =
        FdBondCalculator.rdInstalmentCount(_startDate, _maturityDate);
    if (instalments < 1) return null;

    double? rate;
    if (_inputMode == DepositInputMode.byRate) {
      rate = _typedRate();
    } else {
      final maturityAmount =
          AmountValidator.parse(_maturityAmountController.text);
      // Anything up to the instalments themselves means no interest at all.
      if (maturityAmount == null ||
          maturityAmount <= installment * instalments) {
        return null;
      }
      rate = _findRdRate(installment, maturityAmount);
    }
    if (rate == null) return null;

    final rd = FdBondCalculator.calculateRecurring(
      monthlyInstalment: installment,
      annualRatePercent: rate,
      startDate: _startDate,
      maturityDate: _maturityDate,
    );
    final calculation = FdBondCalculationResult(
      principal: rd.investedSoFar,
      annualRatePercent: rate,
      startDate: _startDate,
      maturityDate: _maturityDate,
      compounding: CompoundingFrequency.monthly,
      currentValue: rd.currentValue,
      maturityValue: rd.maturityValue,
    );
    return FdBondInputResult(
      // Paid in so far: the first instalment from the start date on, so an
      // RD opened this month is never a holding worth 0.
      principal: rd.investedSoFar,
      annualRatePercent: rate,
      startDate: _startDate,
      maturityDate: _maturityDate,
      compounding: CompoundingFrequency.monthly,
      calculation: calculation,
      depositType: DepositType.recurring,
      monthlyInstallment: installment,
      totalToInvest: rd.totalToInvest,
    );
  }

  /// The annual rate at which [installment] a month grows to
  /// [targetMaturity] by the maturity date, found by bisection (maturity
  /// value rises with the rate). Null when no rate up to the cap gets there.
  double? _findRdRate(double installment, double targetMaturity) {
    double maturityAt(double rate) => FdBondCalculator.calculateRecurring(
          monthlyInstalment: installment,
          annualRatePercent: rate,
          startDate: _startDate,
          maturityDate: _maturityDate,
          asOf: _maturityDate,
        ).maturityValue;

    var lo = 0.0;
    var hi = DepositSchedule.maxRatePercent;
    if (maturityAt(hi) < targetMaturity) return null;
    for (var iter = 0; iter < 60; iter++) {
      final mid = (lo + hi) / 2;
      if (maturityAt(mid) < targetMaturity) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final rate = (lo + hi) / 2;
    return rate > 0 ? rate : null;
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      // Matches the asset form's purchase-date range.
      firstDate: DateTime(1990),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _startDate = picked);
      _recalculate();
    }
  }

  Future<void> _pickMaturityDate() async {
    final firstDate = DateUtils.dateOnly(_startDate).add(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      // A start date moved past the old maturity must not put the initial
      // date outside the picker's range (that asserts).
      initialDate:
          _maturityDate.isBefore(firstDate) ? firstDate : _maturityDate,
      firstDate: firstDate,
      lastDate: DateTime(2099, 12, 31),
    );
    if (picked != null) {
      setState(() => _maturityDate = picked);
      _recalculate();
    }
  }

  /// Inline error for a calculator amount: nothing while blank, otherwise
  /// the shared rule (finite and more than 0).
  String? _amountError(TextEditingController controller) =>
      AmountValidator.validate(controller.text, required: false);

  /// The rate field's error: the shared rule, plus the 100% p.a. cap.
  String? get _rateError {
    final basic = _amountError(_rateController);
    if (basic != null) return basic;
    final rate = AmountValidator.parse(_rateController.text);
    if (rate != null && rate > DepositSchedule.maxRatePercent) {
      return 'At most ${DepositSchedule.maxRatePercent.toStringAsFixed(0)}% '
          'p.a.';
    }
    return null;
  }

  /// Prefix for the amount fields, e.g. '₹ ' or 'CHF '.
  String get _symbol =>
      '${AppConstants.currencies[widget.currency] ?? widget.currency} ';

  @override
  Widget build(BuildContext context) {
    final accentColor = widget.isFd
        ? const Color(0xFF1565C0)
        : const Color(0xFF6A1B9A);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // FD / RD toggle (only for deposits, not bonds)
        if (widget.isFd) ...[
          Row(
            children: [
              _typeChip('Fixed Deposit', DepositType.fixed, accentColor),
              const SizedBox(width: 8),
              _typeChip('Recurring Deposit', DepositType.recurring,
                  const Color(0xFF00838F)),
            ],
          ),
          const SizedBox(height: 12),
        ],

        // Input mode toggle
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadii.small),
          ),
          child: Row(
            children: [
              Expanded(
                child: _modeTab(
                  'Enter Interest Rate',
                  DepositInputMode.byRate,
                  Icons.percent,
                  accentColor,
                ),
              ),
              Expanded(
                child: _modeTab(
                  'Enter Maturity Amount',
                  DepositInputMode.byMaturity,
                  Icons.account_balance_wallet,
                  accentColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Principal / Monthly Installment
        if (_depositType == DepositType.recurring) ...[
          TextField(
            controller: _monthlyInstallmentController,
            decoration: InputDecoration(
              labelText: 'Monthly Installment',
              hintText: 'e.g. 5000',
              prefixText: _symbol,
              errorText: _amountError(_monthlyInstallmentController),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
        ] else ...[
          TextField(
            controller: _principalController,
            decoration: InputDecoration(
              labelText: widget.isFd ? 'Principal Amount' : 'Face Value',
              hintText: 'e.g. 500000',
              prefixText: _symbol,
              errorText: _amountError(_principalController),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
        ],

        // Rate OR Maturity Amount
        if (_inputMode == DepositInputMode.byRate) ...[
          TextField(
            controller: _rateController,
            decoration: InputDecoration(
              labelText: widget.isFd
                  ? 'Annual Interest Rate (%)'
                  : 'Coupon Rate (% p.a.)',
              hintText: 'e.g. 7.5',
              suffixText: '% p.a.',
              errorText: _rateError,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ] else ...[
          TextField(
            controller: _maturityAmountController,
            decoration: InputDecoration(
              labelText: _depositType == DepositType.recurring
                  ? 'Expected Maturity Amount'
                  : 'Maturity Amount',
              hintText: 'e.g. 624580',
              prefixText: _symbol,
              helperText: 'App will calculate the interest rate for you',
              errorText: _amountError(_maturityAmountController),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ],
        const SizedBox(height: 12),

        // Start + Maturity dates
        Row(
          children: [
            Expanded(
              child: _DateTile(
                label: 'Start Date',
                date: _startDate,
                onTap: _pickStartDate,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DateTile(
                label: 'Maturity Date',
                date: _maturityDate,
                onTap: _pickMaturityDate,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Compounding (only for FD/Bond by rate, not RD)
        if (_depositType != DepositType.recurring) ...[
          DropdownButtonFormField<CompoundingFrequency>(
            initialValue: _compounding,
            decoration: const InputDecoration(
              labelText: 'Compounding Frequency',
            ),
            items: CompoundingFrequency.values.map((freq) {
              return DropdownMenuItem(
                value: freq,
                child: Text(freq.label),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _compounding = value);
                _recalculate();
              }
            },
          ),
          const SizedBox(height: 12),
        ],

        // Calculation result card
        if (_input != null) ...[
          _CalculationCard(
            result: _input!.calculation,
            isFd: widget.isFd,
            depositType: _depositType,
            totalToInvest: _input!.totalToInvest,
            // Only worth showing when the app derived the rate from the
            // maturity amount — in by-rate mode the user just typed it.
            derivedRate: _inputMode == DepositInputMode.byMaturity
                ? _input!.annualRatePercent
                : null,
            accentColor: accentColor,
            currency: widget.currency,
          ),
        ],
      ],
    );
  }

  Widget _typeChip(String label, DepositType type, Color color) {
    final isSelected = _depositType == type;
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isSelected ? Colors.white : color,
        ),
      ),
      selected: isSelected,
      onSelected: (_) {
        setState(() => _depositType = type);
        _recalculate();
      },
      selectedColor: color,
      backgroundColor: color.withValues(alpha: 0.08),
      checkmarkColor: Colors.white,
      side: BorderSide(
        color: isSelected ? color : color.withValues(alpha: 0.3),
        width: 1,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _modeTab(
      String label, DepositInputMode mode, IconData icon, Color color) {
    final isSelected = _inputMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() => _inputMode = mode);
        _recalculate();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.small),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 14,
                color: isSelected
                    ? Colors.white
                    : AppColors.textSecondaryOn(context)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? Colors.white
                      : AppColors.textSecondaryOn(context),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  const _DateTile({
    required this.label,
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondaryOn(context),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.calendar_today,
                    size: 14, color: AppColors.primary),
                const SizedBox(width: 4),
                Text(
                  '${date.day}/${date.month}/${date.year}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CalculationCard extends StatelessWidget {
  /// For an RD, `principal` is what has been paid in so far.
  final FdBondCalculationResult result;
  final bool isFd;
  final DepositType depositType;
  final double? derivedRate;
  final Color accentColor;
  final String currency;

  /// An RD's instalments over the whole tenure.
  final double? totalToInvest;

  const _CalculationCard({
    required this.result,
    required this.isFd,
    required this.depositType,
    required this.derivedRate,
    required this.accentColor,
    required this.currency,
    this.totalToInvest,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current value
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                result.isMatured ? 'Matured Value' : 'Current Value',
                style: TextStyle(
                  color: AppColors.textSecondaryOn(context),
                  fontSize: 13,
                ),
              ),
              Text(
                _fmt(result.currentValue),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: accentColor,
                  fontSize: 18,
                ),
              ),
            ],
          ),

          // Show derived rate if using maturity mode
          if (derivedRate != null) ...[
            const SizedBox(height: 4),
            Text(
              '≈ ${derivedRate!.toStringAsFixed(2)}% p.a. interest rate',
              style: TextStyle(
                color: AppColors.success,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],

          const SizedBox(height: 8),
          Divider(color: accentColor.withValues(alpha: 0.2), height: 1),
          const SizedBox(height: 8),

          if (depositType == DepositType.recurring) ...[
            _row(context, 'Paid in so far', _fmt(result.principal)),
            _row(context, 'Interest Earned',
                _fmt(result.interestEarnedSoFar),
                color: AppColors.success),
            if (totalToInvest != null)
              _row(context, 'Total to Invest', _fmt(totalToInvest!)),
            _row(context, 'Maturity Value', _fmt(result.maturityValue)),
          ] else ...[
            _row(context, 'Principal', _fmt(result.principal)),
            _row(context, 'Interest Earned',
                _fmt(result.interestEarnedSoFar),
                color: AppColors.success),
            _row(context, 'Maturity Value', _fmt(result.maturityValue)),
          ],

          const SizedBox(height: 10),

          if (!result.isMatured) ...[
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${result.daysRemaining} days left',
                style: TextStyle(
                    color: AppColors.textTertiaryOn(context), fontSize: 11),
              ),
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: result.progressPercent / 100,
                backgroundColor: accentColor.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                minHeight: 6,
              ),
            ),
          ] else
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Matured',
                style: TextStyle(
                  color: AppColors.success,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value,
      {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: AppColors.textSecondaryOn(context), fontSize: 12)),
          Text(value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              )),
        ],
      ),
    );
  }

  /// Compact amount in the holding's currency (Cr/L/K for INR, K/M/B else).
  String _fmt(double value) =>
      CurrencyFormatter.formatCompactCurrency(value, currency);
}
