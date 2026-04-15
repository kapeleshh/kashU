import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/asset_type.dart';
import '../../shared/providers/portfolio_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────────────────────────────────────

class _RebalanceRow {
  final AssetType type;
  final double currentValue;
  final double currentPct;
  final double targetPct;
  final double targetValue;
  final double delta; // positive → buy, negative → sell

  const _RebalanceRow({
    required this.type,
    required this.currentValue,
    required this.currentPct,
    required this.targetPct,
    required this.targetValue,
    required this.delta,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider — persists target allocations in Hive settings box
// ─────────────────────────────────────────────────────────────────────────────

/// Hive key prefix for target allocations: "rebal_{assetTypeName}"
String _rebalKey(AssetType t) => 'rebal_${t.name}';

/// Reads persisted target percentages (0–100) for each AssetType.
/// Returns a mutable map so callers can update it.
Map<AssetType, double> _loadTargets() {
  final box = Hive.box(AppConstants.settingsBox);
  return {
    for (final t in AssetType.values)
      t: (box.get(_rebalKey(t), defaultValue: 0.0) as num).toDouble(),
  };
}

Future<void> _saveTarget(AssetType type, double value) async {
  await Hive.box(AppConstants.settingsBox).put(_rebalKey(type), value);
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class RebalancingScreen extends ConsumerStatefulWidget {
  const RebalancingScreen({super.key});

  @override
  ConsumerState<RebalancingScreen> createState() => _RebalancingScreenState();
}

class _RebalancingScreenState extends ConsumerState<RebalancingScreen> {
  late Map<AssetType, double> _targets;

  @override
  void initState() {
    super.initState();
    _targets = _loadTargets();
  }

  double get _totalTargetPct =>
      _targets.values.fold(0.0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    final assets = ref.watch(allAssetsProvider);
    final baseCurrency = ref.watch(baseCurrencyProvider);

    // Current value per asset type
    final Map<AssetType, double> typeValues = {};
    double totalValue = 0;
    for (final asset in assets) {
      typeValues[asset.type] = (typeValues[asset.type] ?? 0) + asset.currentValue;
      totalValue += asset.currentValue;
    }

    // Only show types that have holdings OR a non-zero target
    final relevantTypes = AssetType.values.where((t) {
      return (typeValues[t] ?? 0) > 0 || (_targets[t] ?? 0) > 0;
    }).toList();

    // Build rebalance rows
    final rows = relevantTypes.map((t) {
      final cur = typeValues[t] ?? 0;
      final curPct = totalValue > 0 ? (cur / totalValue) * 100 : 0.0;
      final tgtPct = _targets[t] ?? 0;
      final tgtValue = totalValue * tgtPct / 100;
      return _RebalanceRow(
        type: t,
        currentValue: cur,
        currentPct: curPct,
        targetPct: tgtPct,
        targetValue: tgtValue,
        delta: tgtValue - cur,
      );
    }).toList();

    final totalTargetPct = _totalTargetPct;
    final isValid = (totalTargetPct - 100).abs() < 0.5 || totalTargetPct == 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rebalancing Calculator'),
        actions: [
          if (!isValid)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${totalTargetPct.toStringAsFixed(0)}%',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.error,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          if (isValid && totalTargetPct > 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${totalTargetPct.toStringAsFixed(0)}%',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.success,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _InfoCard(totalValue: totalValue, baseCurrency: baseCurrency),
          const SizedBox(height: 20),

          if (assets.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  'Add assets to your portfolio first.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else ...[
            Text(
              'Target Allocation',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Set your desired % for each asset class. Total must equal 100%.',
              style:
                  TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 12),

            // Target sliders
            ...relevantTypes.map((t) => _TargetSlider(
                  type: t,
                  currentValue: typeValues[t] ?? 0,
                  totalValue: totalValue,
                  targetPct: _targets[t] ?? 0,
                  baseCurrency: baseCurrency,
                  onChanged: (v) async {
                    setState(() => _targets[t] = v);
                    await _saveTarget(t, v);
                  },
                )),

            if (!isValid && totalTargetPct > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Total is ${totalTargetPct.toStringAsFixed(1)}% — adjust sliders to reach 100%.',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.error),
                ),
              ),
            ],

            // Show recommendations only when targets are valid and set
            if (isValid && totalTargetPct > 0 && totalValue > 0) ...[
              const SizedBox(height: 24),
              Text(
                'Rebalancing Actions',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 12),
              ...rows.map((row) => _ActionRow(
                    row: row,
                    baseCurrency: baseCurrency,
                  )),
            ],

            const SizedBox(height: 24),
            _Disclaimer(),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final double totalValue;
  final String baseCurrency;

  const _InfoCard({required this.totalValue, required this.baseCurrency});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.balance_outlined, color: AppColors.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Portfolio value: ${CurrencyFormatter.formatCurrency(totalValue, baseCurrency)}',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Set your ideal allocation below. The calculator will show '
                  'how much to buy or sell in each asset class.',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TargetSlider extends StatelessWidget {
  final AssetType type;
  final double currentValue;
  final double totalValue;
  final double targetPct;
  final String baseCurrency;
  final ValueChanged<double> onChanged;

  const _TargetSlider({
    required this.type,
    required this.currentValue,
    required this.totalValue,
    required this.targetPct,
    required this.baseCurrency,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final currentPct =
        totalValue > 0 ? (currentValue / totalValue) * 100 : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: type.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(type.icon, color: type.color, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      type.displayName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${targetPct.toStringAsFixed(0)}%',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppColors.primary),
                      ),
                      Text(
                        'now ${currentPct.toStringAsFixed(1)}%',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textTertiary),
                      ),
                    ],
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: type.color,
                  thumbColor: type.color,
                  overlayColor: type.color.withValues(alpha: 0.12),
                  inactiveTrackColor: type.color.withValues(alpha: 0.2),
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 8),
                ),
                child: Slider(
                  value: targetPct,
                  min: 0,
                  max: 100,
                  divisions: 100,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final _RebalanceRow row;
  final String baseCurrency;

  const _ActionRow({required this.row, required this.baseCurrency});

  @override
  Widget build(BuildContext context) {
    final isBuy = row.delta > 0;
    final isBalanced = row.delta.abs() < 1;
    final actionColor = isBalanced
        ? AppColors.textTertiary
        : isBuy
            ? AppColors.success
            : AppColors.error;
    final actionLabel = isBalanced
        ? 'Balanced'
        : isBuy
            ? 'Buy'
            : 'Sell';
    final actionIcon = isBalanced
        ? Icons.check_circle_outline
        : isBuy
            ? Icons.arrow_upward
            : Icons.arrow_downward;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: row.type.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(row.type.icon, color: row.type.color, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.type.displayName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    Text(
                      '${row.currentPct.toStringAsFixed(1)}% → ${row.targetPct.toStringAsFixed(0)}%  '
                      '(${CurrencyFormatter.formatCurrency(row.currentValue, baseCurrency)} → '
                      '${CurrencyFormatter.formatCurrency(row.targetValue, baseCurrency)})',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Icon(actionIcon, size: 14, color: actionColor),
                      const SizedBox(width: 4),
                      Text(
                        actionLabel,
                        style: TextStyle(
                            fontSize: 12,
                            color: actionColor,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  if (!isBalanced)
                    Text(
                      CurrencyFormatter.formatCurrency(row.delta.abs(), baseCurrency),
                      style: TextStyle(
                          fontSize: 13,
                          color: actionColor,
                          fontWeight: FontWeight.bold),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '⚠ This calculator is for planning purposes only. It does not account '
        'for taxes, exit loads, lock-in periods, or brokerage charges. '
        'Consult a qualified financial advisor before rebalancing.',
        style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
      ),
    );
  }
}
