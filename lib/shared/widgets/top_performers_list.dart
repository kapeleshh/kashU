import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/asset.dart';
import '../../data/models/asset_type.dart';

/// Soft rounded list of holdings (top gainers / losers), each a pastel card
/// with a gradient avatar and a colour-coded change.
class TopPerformersList extends StatelessWidget {
  final List<Asset>? assets;
  final bool isGainers;
  final bool isLoading;

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

    return Column(
      children: [
        for (var i = 0; i < assets!.length; i++) ...[
          if (i > 0) const SizedBox(height: 9),
          _tile(context, assets![i]),
        ],
      ],
    );
  }

  Widget _tile(BuildContext context, Asset asset) {
    final isProfit = asset.gainLossPercentage >= 0;
    final changeColor =
        isProfit ? AppColors.gainOn(context) : AppColors.lossOn(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.tile),
        boxShadow: AppShadows.soft(opacity: 0.16, y: 10, blur: 24),
      ),
      child: Row(
        children: [
          _avatar(asset),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  asset.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.heading(
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  _subtitle(asset),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                CurrencyFormatter.formatCompactINR(asset.currentValue),
                style: AppTheme.heading(
                  size: 13.5,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${isProfit ? '▲' : '▼'} ${CurrencyFormatter.formatPercentage(asset.gainLossPercentage.abs(), showSign: false)}',
                style: AppTheme.body(
                  size: 11.5,
                  weight: FontWeight.w800,
                  color: changeColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _avatar(Asset asset) {
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: softAvatarGradient(asset.type.color),
        borderRadius: BorderRadius.circular(AppRadii.avatar),
      ),
      child: Text(
        _initials(asset),
        style: AppTheme.heading(size: 14, color: Colors.white),
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

  String _subtitle(Asset asset) {
    final unit = asset.type.unitLabel;
    final qty = CurrencyFormatter.formatQuantity(asset.quantity);
    final qtyPart = unit.isEmpty ? '' : '$qty $unit · ';
    return '$qtyPart${asset.type.displayName}';
  }

  Widget _buildLoading() {
    return Column(
      children: List.generate(
        3,
        (i) => Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 9),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.shimmerBase,
              borderRadius: BorderRadius.circular(AppRadii.tile),
            ),
          ),
        ),
      ),
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
