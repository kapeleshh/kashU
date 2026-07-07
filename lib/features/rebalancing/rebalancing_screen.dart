import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/asset_type.dart';
import '../../shared/providers/portfolio_provider.dart';
import '../../shared/widgets/soft_disclaimer.dart';

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
          if (totalTargetPct > 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(child: _TotalChip(pct: totalTargetPct, isValid: isValid)),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _InfoCard(totalValue: totalValue, baseCurrency: baseCurrency),
            const SizedBox(height: 20),

            if (assets.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'Add assets to your portfolio first.',
                    style: AppTheme.body(
                      size: 13,
                      color: AppColors.textSecondaryOn(context),
                    ),
                  ),
                ),
              )
            else ...[
              const _SectionHeader(
                title: 'Target Allocation',
                subtitle:
                    'Set your desired % for each asset class. Total must equal 100%.',
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
                _Banner(
                  icon: Icons.error_outline_rounded,
                  color: AppColors.lossOn(context),
                  text: 'Adjust sliders to reach 100%',
                ),
              ],

              // Show recommendations only when targets are valid and set
              if (isValid && totalTargetPct > 0 && totalValue > 0) ...[
                const SizedBox(height: 24),
                const _SectionHeader(title: 'Rebalancing Actions'),
                const SizedBox(height: 12),
                ...rows.map((row) => _ActionRow(
                      row: row,
                      baseCurrency: baseCurrency,
                    )),
              ],

              const SizedBox(height: 24),
              const SoftDisclaimer(
                'For planning only — consult a financial advisor before acting.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Small pill shown in the app bar with the running total of target %.
class _TotalChip extends StatelessWidget {
  final double pct;
  final bool isValid;

  const _TotalChip({required this.pct, required this.isValid});

  @override
  Widget build(BuildContext context) {
    final color = isValid ? AppColors.gainOn(context) : AppColors.lossOn(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        '${pct.toStringAsFixed(0)}%',
        style: AppTheme.body(size: 12.5, weight: FontWeight.w800, color: color),
      ),
    );
  }
}

/// Quicksand section header with an optional supporting line.
class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _SectionHeader({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              subtitle!,
              style: AppTheme.body(
                size: 12,
                weight: FontWeight.w600,
                color: AppColors.textTertiaryOn(context),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Soft inline banner (validation hint / warnings).
class _Banner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _Banner({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.tile),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style:
                  AppTheme.body(size: 12, weight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final double totalValue;
  final String baseCurrency;

  const _InfoCard({required this.totalValue, required this.baseCurrency});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: AppShadows.glow(AppColors.primary, opacity: 0.45),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(AppRadii.avatar),
            ),
            child: const Icon(Icons.balance_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Portfolio value',
                  style: AppTheme.body(
                    size: 11.5,
                    weight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  CurrencyFormatter.formatCurrency(totalValue, baseCurrency),
                  style: AppTheme.heading(size: 20, color: Colors.white),
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
      padding: const EdgeInsets.only(bottom: 9),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 9),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadii.tile),
          boxShadow: AppShadows.soft(opacity: 0.16, y: 10, blur: 24),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: softAvatarGradient(type.color),
                    borderRadius: BorderRadius.circular(AppRadii.avatar),
                  ),
                  child: Icon(type.icon, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    type.displayName,
                    style: AppTheme.heading(
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${targetPct.toStringAsFixed(0)}%',
                      style: AppTheme.heading(size: 16, color: type.color),
                    ),
                    Text(
                      'now ${currentPct.toStringAsFixed(1)}%',
                      style: AppTheme.body(
                        size: 11,
                        weight: FontWeight.w600,
                        color: AppColors.textTertiaryOn(context),
                      ),
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
                trackHeight: 4,
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
        ? AppColors.textTertiaryOn(context)
        : isBuy
            ? AppColors.gainOn(context)
            : AppColors.lossOn(context);
    final actionLabel = isBalanced
        ? 'Balanced'
        : '${isBuy ? 'Buy' : 'Sell'} '
            '${CurrencyFormatter.formatCurrency(row.delta.abs(), baseCurrency)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadii.tile),
          boxShadow: AppShadows.soft(opacity: 0.16, y: 10, blur: 24),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: softAvatarGradient(row.type.color),
                borderRadius: BorderRadius.circular(AppRadii.avatar),
              ),
              child: Icon(row.type.icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.type.displayName,
                    style: AppTheme.heading(
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${CurrencyFormatter.formatCurrency(row.currentValue, baseCurrency)} → '
                    '${CurrencyFormatter.formatCurrency(row.targetValue, baseCurrency)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(
                      size: 11,
                      weight: FontWeight.w600,
                      color: AppColors.textSecondaryOn(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              actionLabel,
              style: AppTheme.heading(size: 14, color: actionColor),
            ),
          ],
        ),
      ),
    );
  }
}
