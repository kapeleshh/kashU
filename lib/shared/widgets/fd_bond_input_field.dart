import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../services/fd_bond_calculator.dart';

/// Result passed back to the parent when the user fills in FD/Bond details.
class FdBondInputResult {
  final double principal;
  final double annualRatePercent;
  final DateTime startDate;
  final DateTime maturityDate;
  final CompoundingFrequency compounding;
  final FdBondCalculationResult calculation;

  const FdBondInputResult({
    required this.principal,
    required this.annualRatePercent,
    required this.startDate,
    required this.maturityDate,
    required this.compounding,
    required this.calculation,
  });
}

/// A smart input widget for Fixed Deposits and Bonds.
///
/// Shows fields for:
/// - Principal amount
/// - Annual interest rate
/// - Start date
/// - Maturity date
/// - Compounding frequency
///
/// Automatically calculates and displays:
/// - Current value (as of today)
/// - Maturity value
/// - Interest earned so far
/// - Progress bar
///
/// Calls [onChanged] whenever any field changes with the latest calculation.
class FdBondInputField extends StatefulWidget {
  final bool isFd; // true = Fixed Deposit, false = Bond
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

  DateTime _startDate = DateTime.now();
  DateTime _maturityDate = DateTime.now().add(const Duration(days: 365));
  CompoundingFrequency _compounding = CompoundingFrequency.quarterly;

  FdBondCalculationResult? _result;

  @override
  void initState() {
    super.initState();
    _principalController.addListener(_recalculate);
    _rateController.addListener(_recalculate);
  }

  @override
  void dispose() {
    _principalController.dispose();
    _rateController.dispose();
    super.dispose();
  }

  void _recalculate() {
    final principal = double.tryParse(_principalController.text);
    final rate = double.tryParse(_rateController.text);

    if (principal == null || principal <= 0 || rate == null || rate <= 0) {
      setState(() => _result = null);
      return;
    }

    if (_maturityDate.isBefore(_startDate)) {
      setState(() => _result = null);
      return;
    }

    final result = FdBondCalculator.calculate(
      principal: principal,
      annualRatePercent: rate,
      startDate: _startDate,
      maturityDate: _maturityDate,
      compounding: _compounding,
    );

    setState(() => _result = result);

    widget.onChanged(FdBondInputResult(
      principal: principal,
      annualRatePercent: rate,
      startDate: _startDate,
      maturityDate: _maturityDate,
      compounding: _compounding,
      calculation: result,
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
    final label = widget.isFd ? 'Fixed Deposit' : 'Bond';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Icon(
              widget.isFd ? Icons.account_balance : Icons.receipt_long,
              color: widget.isFd
                  ? const Color(0xFF1565C0)
                  : const Color(0xFF6A1B9A),
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              '$label Details',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Principal
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

        // Interest Rate
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
        const SizedBox(height: 12),

        // Start Date + Maturity Date
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

        // Compounding Frequency
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

        // Calculation result card
        if (_result != null) ...[
          const SizedBox(height: 16),
          _CalculationCard(result: _result!, isFd: widget.isFd),
        ],
      ],
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
          border: Border.all(color: AppColors.divider),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary,
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

  const _CalculationCard({required this.result, required this.isFd});

  @override
  Widget build(BuildContext context) {
    final color = isFd
        ? const Color(0xFF1565C0)
        : const Color(0xFF6A1B9A);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current value (big)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                result.isMatured ? 'Matured Value' : 'Current Value',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              Text(
                '₹${_fmt(result.currentValue)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: 18,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),
          Divider(color: color.withValues(alpha: 0.2), height: 1),
          const SizedBox(height: 8),

          // Details
          _row('Principal', '₹${_fmt(result.principal)}'),
          _row('Interest Earned', '₹${_fmt(result.interestEarnedSoFar)}',
              color: AppColors.success),
          _row('Maturity Value', '₹${_fmt(result.maturityValue)}'),
          _row('Total Interest', '₹${_fmt(result.totalInterestAtMaturity)}'),

          const SizedBox(height: 10),

          // Progress bar
          if (!result.isMatured) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${result.daysElapsed} days elapsed',
                  style: TextStyle(
                      color: AppColors.textTertiary, fontSize: 11),
                ),
                Text(
                  '${result.daysRemaining} days left',
                  style: TextStyle(
                      color: AppColors.textTertiary, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: result.progressPercent / 100,
                backgroundColor: color.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(color),
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

  Widget _row(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
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
