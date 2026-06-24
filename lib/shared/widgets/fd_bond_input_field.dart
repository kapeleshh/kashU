import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../services/fd_bond_calculator.dart';

/// Deposit sub-type: Fixed Deposit or Recurring Deposit
enum DepositType { fixed, recurring }

/// Input mode: user knows the interest rate, or knows the maturity amount
enum DepositInputMode { byRate, byMaturity }

/// Result passed back to the parent when the user fills in deposit details.
class FdBondInputResult {
  final double principal;
  final double annualRatePercent;
  final DateTime startDate;
  final DateTime maturityDate;
  final CompoundingFrequency compounding;
  final FdBondCalculationResult calculation;
  final DepositType depositType;
  final double? monthlyInstallment; // for RD

  const FdBondInputResult({
    required this.principal,
    required this.annualRatePercent,
    required this.startDate,
    required this.maturityDate,
    required this.compounding,
    required this.calculation,
    required this.depositType,
    this.monthlyInstallment,
  });
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
  final void Function(FdBondInputResult result) onChanged;

  const FdBondInputField({
    super.key,
    required this.isFd,
    required this.onChanged,
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

  FdBondCalculationResult? _result;
  double? _derivedRate; // back-calculated rate when using byMaturity mode

  @override
  void initState() {
    super.initState();
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

  void _recalculate() {
    final principal = double.tryParse(_principalController.text);
    if (principal == null || principal <= 0) {
      setState(() { _result = null; _derivedRate = null; });
      return;
    }
    if (_maturityDate.isBefore(_startDate)) {
      setState(() { _result = null; _derivedRate = null; });
      return;
    }

    if (_depositType == DepositType.recurring) {
      _recalculateRd(principal);
      return;
    }

    if (_inputMode == DepositInputMode.byRate) {
      _recalculateByRate(principal);
    } else {
      _recalculateByMaturity(principal);
    }
  }

  void _recalculateByRate(double principal) {
    final rate = double.tryParse(_rateController.text);
    if (rate == null || rate <= 0) {
      setState(() { _result = null; _derivedRate = null; });
      return;
    }

    final result = FdBondCalculator.calculate(
      principal: principal,
      annualRatePercent: rate,
      startDate: _startDate,
      maturityDate: _maturityDate,
      compounding: _compounding,
    );

    setState(() {
      _result = result;
      _derivedRate = rate;
    });

    _notifyParent(result, rate, principal);
  }

  void _recalculateByMaturity(double principal) {
    final maturityAmount = double.tryParse(_maturityAmountController.text);
    if (maturityAmount == null || maturityAmount <= principal) {
      setState(() { _result = null; _derivedRate = null; });
      return;
    }

    // Back-calculate the annual interest rate from maturity amount
    final totalDays = _maturityDate.difference(_startDate).inDays;
    if (totalDays <= 0) {
      setState(() { _result = null; _derivedRate = null; });
      return;
    }
    final tTotal = totalDays / 365.0;
    final n = _compounding == CompoundingFrequency.simple
        ? 1.0
        : _compounding.periodsPerYear.toDouble();

    double derivedRate;
    if (_compounding == CompoundingFrequency.simple) {
      // A = P(1 + rt) → r = (A/P - 1) / t
      derivedRate = ((maturityAmount / principal) - 1) / tTotal * 100;
    } else {
      // A = P(1 + r/n)^(nt) → r = n × ((A/P)^(1/(nt)) - 1)
      final ratio = maturityAmount / principal;
      final exponent = 1.0 / (n * tTotal);
      derivedRate = n * (math.pow(ratio, exponent).toDouble() - 1) * 100;
    }

    if (derivedRate <= 0 || derivedRate > 100) {
      setState(() { _result = null; _derivedRate = null; });
      return;
    }

    final result = FdBondCalculator.calculate(
      principal: principal,
      annualRatePercent: derivedRate,
      startDate: _startDate,
      maturityDate: _maturityDate,
      compounding: _compounding,
    );

    setState(() {
      _result = result;
      _derivedRate = derivedRate;
    });

    _notifyParent(result, derivedRate, principal);
  }

  void _recalculateRd(double monthlyInstallment) {
    final installment = double.tryParse(_monthlyInstallmentController.text);
    if (installment == null || installment <= 0) {
      setState(() { _result = null; _derivedRate = null; });
      return;
    }

    double rate;
    if (_inputMode == DepositInputMode.byRate) {
      final r = double.tryParse(_rateController.text);
      if (r == null || r <= 0) {
        setState(() { _result = null; _derivedRate = null; });
        return;
      }
      rate = r;
    } else {
      // For RD by maturity: back-calculate rate
      final maturityAmount = double.tryParse(_maturityAmountController.text);
      if (maturityAmount == null || maturityAmount <= 0) {
        setState(() { _result = null; _derivedRate = null; });
        return;
      }
      final months = _maturityDate.difference(_startDate).inDays ~/ 30;
      if (months <= 0) {
        setState(() { _result = null; _derivedRate = null; });
        return;
      }
      // Approximate: use binary search to find rate
      rate = _findRdRate(installment, maturityAmount, months);
      if (rate <= 0) {
        setState(() { _result = null; _derivedRate = null; });
        return;
      }
    }

    // RD maturity formula: M = R × [(1+i)^n - 1] / i × (1+i)
    // where i = monthly rate, n = number of months
    final months = _maturityDate.difference(_startDate).inDays ~/ 30;
    final i = rate / 100 / 12; // monthly rate
    final n = months.toDouble();
    final maturityValue = installment * ((math.pow(1 + i, n) - 1) / i) * (1 + i);

    // Current value: proportional to months elapsed
    final elapsedMonths = DateTime.now().difference(_startDate).inDays ~/ 30;
    final effectiveMonths = elapsedMonths.clamp(0, months);
    final currentValue = installment * ((math.pow(1 + i, effectiveMonths) - 1) / i) * (1 + i);
    final totalInvested = installment * months;
    final principal = installment * effectiveMonths; // invested so far

    // Create a synthetic result using FdBondCalculationResult
    final result = FdBondCalculationResult(
      principal: totalInvested, // total to be invested
      annualRatePercent: rate,
      startDate: _startDate,
      maturityDate: _maturityDate,
      compounding: CompoundingFrequency.monthly,
      currentValue: currentValue.clamp(0, maturityValue),
      maturityValue: maturityValue,
    );

    setState(() {
      _result = result;
      _derivedRate = rate;
    });

    widget.onChanged(FdBondInputResult(
      principal: principal,
      annualRatePercent: rate,
      startDate: _startDate,
      maturityDate: _maturityDate,
      compounding: CompoundingFrequency.monthly,
      calculation: result,
      depositType: DepositType.recurring,
      monthlyInstallment: installment,
    ));
  }

  /// Binary search to find RD rate given maturity amount
  double _findRdRate(double installment, double targetMaturity, int months) {
    double lo = 0.01, hi = 50.0;
    for (int iter = 0; iter < 100; iter++) {
      final mid = (lo + hi) / 2;
      final i = mid / 100 / 12;
      final n = months.toDouble();
      final m = installment * ((math.pow(1 + i, n) - 1) / i) * (1 + i);
      if ((m - targetMaturity).abs() < 0.01) { return mid; }
      if (m < targetMaturity) { lo = mid; } else { hi = mid; }
    }
    return (lo + hi) / 2;
  }

  void _notifyParent(FdBondCalculationResult result, double rate, double principal) {
    widget.onChanged(FdBondInputResult(
      principal: principal,
      annualRatePercent: rate,
      startDate: _startDate,
      maturityDate: _maturityDate,
      compounding: _compounding,
      calculation: result,
      depositType: _depositType,
    ));
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _startDate = picked);
      _recalculate();
    }
  }

  Future<void> _pickMaturityDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _maturityDate,
      firstDate: _startDate.add(const Duration(days: 1)),
      lastDate: DateTime(2060),
    );
    if (picked != null) {
      setState(() => _maturityDate = picked);
      _recalculate();
    }
  }

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
            decoration: const InputDecoration(
              labelText: 'Monthly Installment (₹)',
              hintText: 'e.g. 5000',
              prefixText: '₹ ',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
        ] else ...[
          TextField(
            controller: _principalController,
            decoration: InputDecoration(
              labelText: widget.isFd ? 'Principal Amount (₹)' : 'Face Value (₹)',
              hintText: 'e.g. 500000',
              prefixText: '₹ ',
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
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ] else ...[
          TextField(
            controller: _maturityAmountController,
            decoration: InputDecoration(
              labelText: _depositType == DepositType.recurring
                  ? 'Expected Maturity Amount (₹)'
                  : 'Maturity Amount (₹)',
              hintText: 'e.g. 624580',
              prefixText: '₹ ',
              helperText: 'App will calculate the interest rate for you',
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
        if (_result != null) ...[
          _CalculationCard(
            result: _result!,
            isFd: widget.isFd,
            depositType: _depositType,
            derivedRate: _derivedRate,
            accentColor: accentColor,
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
        setState(() {
          _depositType = type;
          _result = null;
        });
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
        setState(() {
          _inputMode = mode;
          _result = null;
        });
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
  final FdBondCalculationResult result;
  final bool isFd;
  final DepositType depositType;
  final double? derivedRate;
  final Color accentColor;

  const _CalculationCard({
    required this.result,
    required this.isFd,
    required this.depositType,
    required this.derivedRate,
    required this.accentColor,
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
                '₹${_fmt(result.currentValue)}',
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
            _row(context, 'Total to Invest', '₹${_fmt(result.principal)}'),
            _row(context, 'Interest Earned',
                '₹${_fmt(result.interestEarnedSoFar)}',
                color: AppColors.success),
            _row(context, 'Maturity Value', '₹${_fmt(result.maturityValue)}'),
          ] else ...[
            _row(context, 'Principal', '₹${_fmt(result.principal)}'),
            _row(context, 'Interest Earned',
                '₹${_fmt(result.interestEarnedSoFar)}',
                color: AppColors.success),
            _row(context, 'Maturity Value', '₹${_fmt(result.maturityValue)}'),
            _row(context, 'Total Interest',
                '₹${_fmt(result.totalInterestAtMaturity)}'),
          ],

          const SizedBox(height: 10),

          if (!result.isMatured) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${result.daysElapsed} days elapsed',
                  style: TextStyle(
                      color: AppColors.textTertiaryOn(context), fontSize: 11),
                ),
                Text(
                  '${result.daysRemaining} days left',
                  style: TextStyle(
                      color: AppColors.textTertiaryOn(context), fontSize: 11),
                ),
              ],
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
                '✅ Matured',
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

  String _fmt(double value) {
    if (value >= 10000000) {
      return '${(value / 10000000).toStringAsFixed(2)} Cr';
    } else if (value >= 100000) {
      return '${(value / 100000).toStringAsFixed(2)} L';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(2)} K';
    }
    return value.toStringAsFixed(2);
  }
}
