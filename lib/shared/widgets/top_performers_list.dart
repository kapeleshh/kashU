import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/asset.dart';
import '../../data/models/asset_type.dart';

/// "On the move" — a horizontal row of compact mover mini-cards matching the
/// C·Soft dashboard: a small gradient icon tile, the holding name, and a
/// colour-coded % change. (Full holding rows live on the Assets screen.)
class TopPerformersList extends StatelessWidget {
  final List<Asset>? assets;
  final bool isGainers;
  final bool isLoading;

  /// How many movers fit in the row before it gets too cramped.
  static const _maxCards = 4;

  const TopPerformersList({
    super.key,
    required this.assets,
    required this.isGainers,
  }) : isLoading = false;

  const TopPerformersList.loading({super.key})
      : assets = null,
        isGainers = true,
        isLoading = true;

  @override
  Widget build(BuildContext context) {
    if (isLoading) return _buildLoading();
    if (assets == null || assets!.isEmpty) return _buildEmpty(context);

    final shown = assets!.take(_maxCards).toList();
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(width: 9),
            Expanded(child: _miniCard(context, shown[i])),
          ],
        ],
      ),
    );
  }

  Widget _miniCard(BuildContext context, Asset asset) {
    final isProfit = asset.gainLossPercentage >= 0;
    final changeColor =
        isProfit ? AppColors.gainOn(context) : AppColors.lossOn(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.tile),
        boxShadow: AppShadows.soft(opacity: 0.16, y: 10, blur: 22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: softAvatarGradient(asset.type.color),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              _initials(asset),
              style: AppTheme.heading(size: 11, color: Colors.white),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            asset.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.body(
              size: 11.5,
              weight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${isProfit ? '▲' : '▼'} ${CurrencyFormatter.formatPercentage(asset.gainLossPercentage.abs(), showSign: false)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.body(size: 11, weight: FontWeight.w800, color: changeColor),
          ),
        ],
      ),
    );
  }

  String _initials(Asset asset) {
    final src = (asset.symbol?.trim().isNotEmpty ?? false)
        ? asset.symbol!.trim()
        : asset.name.trim();
    if (src.isEmpty) return '?';
    final letters = src.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (letters.isEmpty) return src.characters.first;
    return letters.length >= 2
        ? letters.substring(0, 2).toUpperCase()
        : letters.substring(0, 1).toUpperCase();
  }

  Widget _buildLoading() {
    return Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 9),
          Expanded(
            child: Container(
              height: 78,
              decoration: BoxDecoration(
                color: AppColors.shimmerBase,
                borderRadius: BorderRadius.circular(AppRadii.tile),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.tile),
        boxShadow: AppShadows.soft(opacity: 0.12),
      ),
      child: Center(
        child: Text(
          isGainers ? 'No gainers yet' : 'No losers yet',
          style: AppTheme.body(
            size: 13,
            color: AppColors.textSecondaryOn(context),
          ),
        ),
      ),
    );
  }
}
