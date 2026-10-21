import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/asset_type.dart';

/// Each type's share of [allocation] in whole percent.
///
/// [allocation] holds base-currency *amounts* per type (see
/// portfolioSummaryProvider), so the share is taken against their own sum —
/// not the portfolio's current value, which is 0 when the summary falls back
/// to invested amounts before the first price refresh. Largest-remainder
/// rounding makes the legend add up to exactly 100. Non-positive and
/// non-finite amounts are dropped; nothing positive to share yields `{}`.
Map<AssetType, int> allocationPercentages(Map<AssetType, double> allocation) {
  final positive = {
    for (final e in allocation.entries)
      if (e.value.isFinite && e.value > 0) e.key: e.value,
  };
  final total = positive.values.fold(0.0, (s, v) => s + v);
  if (total <= 0 || !total.isFinite) return {};

  final exact = {
    for (final e in positive.entries) e.key: e.value / total * 100
  };
  final result = {for (final e in exact.entries) e.key: e.value.floor()};
  var leftover = 100 - result.values.fold(0, (s, v) => s + v);

  // Hand the points lost to flooring to the largest remainders (ties go to
  // the larger holding, so the order is deterministic).
  final byRemainder = exact.keys.toList()
    ..sort((a, b) {
      final ra = exact[a]! - result[a]!;
      final rb = exact[b]! - result[b]!;
      final byRem = rb.compareTo(ra);
      return byRem != 0 ? byRem : positive[b]!.compareTo(positive[a]!);
    });
  for (final type in byRemainder) {
    if (leftover <= 0) break;
    result[type] = result[type]! + 1;
    leftover--;
  }
  return result;
}

/// "Your mix" — a soft donut with a centred holdings count and a
/// percentage legend.
class AssetAllocationChart extends StatelessWidget {
  /// Base-currency amount per asset type. Shares are derived here, so the
  /// caller passes money, not percentages.
  final Map<AssetType, double>? allocation;
  final int assetCount;
  final bool isLoading;

  const AssetAllocationChart({
    super.key,
    required this.allocation,
    this.assetCount = 0,
  }) : isLoading = false;

  const AssetAllocationChart.loading({super.key})
      : allocation = null,
        assetCount = 0,
        isLoading = true;

  @override
  Widget build(BuildContext context) {
    if (isLoading) return _shell(context, child: _loadingBody());
    final percentages = allocation == null
        ? const <AssetType, int>{}
        : allocationPercentages(allocation!);
    if (percentages.isEmpty) {
      return _shell(context, child: _emptyBody(context));
    }

    // Only types with a positive amount — the same set percentages covers.
    final entries = allocation!.entries
        .where((e) => percentages.containsKey(e.key))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _shell(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your mix', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 13),
          Row(
            children: [
              SizedBox(
                width: 108,
                height: 108,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 30,
                        startDegreeOffset: -90,
                        sections: [
                          for (final e in entries)
                            PieChartSectionData(
                              value: e.value,
                              color: e.key.color,
                              radius: 18,
                              showTitle: false,
                            ),
                        ],
                      ),
                    ),
                    Text(
                      '$assetCount ${assetCount == 1 ? 'holding' : 'holdings'}',
                      textAlign: TextAlign.center,
                      style: AppTheme.body(
                        size: 11,
                        weight: FontWeight.w700,
                        color: AppColors.textSecondaryOn(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    for (final e in entries)
                      _legendRow(context, e.key, percentages[e.key]!),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendRow(BuildContext context, AssetType type, int percent) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration:
                BoxDecoration(color: type.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              type.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.body(
                size: 11.5,
                weight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          Text(
            // A real but tiny slice still deserves a visible figure.
            percent == 0 ? '<1%' : '$percent%',
            style: AppTheme.body(
              size: 11.5,
              weight: FontWeight.w700,
              color: AppColors.textSecondaryOn(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shell(BuildContext context, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: AppShadows.soft(),
      ),
      child: child,
    );
  }

  Widget _loadingBody() {
    return Row(
      children: [
        Container(
          width: 108,
          height: 108,
          decoration: const BoxDecoration(
            color: AppColors.shimmerBase,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            children: List.generate(
              4,
              (_) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Container(
                  height: 11,
                  decoration: BoxDecoration(
                    color: AppColors.shimmerBase,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyBody(BuildContext context) {
    return Column(
      children: [
        Icon(Icons.pie_chart_outline,
            size: 56, color: AppColors.textSecondaryOn(context)),
        const SizedBox(height: 12),
        Text(
          'No allocation yet',
          style: AppTheme.body(
            size: 13,
            color: AppColors.textSecondaryOn(context),
          ),
        ),
      ],
    );
  }
}
