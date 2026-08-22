import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/asset_type.dart';

/// "Your mix" — a soft donut with a centred holdings count and a
/// percentage legend.
class AssetAllocationChart extends StatelessWidget {
  final Map<AssetType, double>? allocation;
  final double totalValue;
  final int assetCount;
  final bool isLoading;

  const AssetAllocationChart({
    super.key,
    required this.allocation,
    this.totalValue = 0,
    this.assetCount = 0,
  }) : isLoading = false;

  const AssetAllocationChart.loading({super.key})
      : allocation = null,
        totalValue = 0,
        assetCount = 0,
        isLoading = true;

  @override
  Widget build(BuildContext context) {
    if (isLoading) return _shell(context, child: _loadingBody());
    if (allocation == null || allocation!.isEmpty) {
      return _shell(context, child: _emptyBody(context));
    }

    final entries = allocation!.entries.toList()
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
                    for (final e in entries) _legendRow(context, e),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendRow(BuildContext context, MapEntry<AssetType, double> e) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: e.key.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              e.key.displayName,
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
            '${e.value.toStringAsFixed(0)}%',
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
