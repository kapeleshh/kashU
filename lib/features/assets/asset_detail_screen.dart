import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/asset.dart';
import '../../data/models/asset_type.dart';
import '../../shared/providers/portfolio_provider.dart';
import 'add_asset_screen.dart';

class AssetDetailScreen extends ConsumerWidget {
  final Asset asset;

  const AssetDetailScreen({super.key, required this.asset});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isProfit = asset.gainLossPercentage >= 0;
    final color = isProfit ? AppColors.success : AppColors.error;

    return Scaffold(
      appBar: AppBar(
        title: Text(asset.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => _editAsset(context, ref),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: asset.type.color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          asset.type.icon,
                          color: asset.type.color,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              asset.name,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (asset.symbol != null)
                              Text(
                                asset.symbol!,
                                style: TextStyle(
                                  color: AppColors.textTertiary,
                                  fontSize: 14,
                                ),
                              ),
                            Text(
                              asset.type.displayName,
                              style: TextStyle(
                                color: asset.type.color,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Current Value
                  Text(
                    CurrencyFormatter.formatINR(asset.currentValue),
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isProfit ? Icons.arrow_upward : Icons.arrow_downward,
                          color: color,
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${CurrencyFormatter.formatINR(asset.gainLoss.abs())} (${CurrencyFormatter.formatPercentage(asset.gainLossPercentage)})',
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Details Section
            Text(
              'Details',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _buildDetailRow('Quantity', '${CurrencyFormatter.formatQuantity(asset.quantity)} ${asset.type.unitLabel}'.trim()),
                  _buildDivider(),
                  _buildDetailRow('Purchase Price', CurrencyFormatter.formatINR(asset.purchasePrice)),
                  _buildDivider(),
                  _buildDetailRow('Current Price', CurrencyFormatter.formatINR(asset.currentPrice)),
                  _buildDivider(),
                  _buildDetailRow('Total Invested', CurrencyFormatter.formatINR(asset.totalInvested)),
                  _buildDivider(),
                  _buildDetailRow('Purchase Date', '${asset.purchaseDate.day}/${asset.purchaseDate.month}/${asset.purchaseDate.year}'),
                  if (asset.platform != null) ...[
                    _buildDivider(),
                    _buildDetailRow('Platform', asset.platform!),
                  ],
                  _buildDivider(),
                  _buildDetailRow('Currency', asset.currency),
                ],
              ),
            ),

            if (asset.notes != null && asset.notes!.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                AppStrings.notes,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  asset.notes!,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Update Price Section
            Text(
              AppStrings.updatePrices,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _UpdatePriceCard(asset: asset),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(color: AppColors.divider, height: 1);
  }

  void _editAsset(BuildContext context, WidgetRef ref) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddAssetScreen(existingAsset: asset),
      ),
    ).then((_) {
      ref.invalidate(allAssetsProvider);
      Navigator.pop(context);
    });
  }
}

class _UpdatePriceCard extends ConsumerStatefulWidget {
  final Asset asset;

  const _UpdatePriceCard({required this.asset});

  @override
  ConsumerState<_UpdatePriceCard> createState() => _UpdatePriceCardState();
}

class _UpdatePriceCardState extends ConsumerState<_UpdatePriceCard> {
  late TextEditingController _priceController;

  @override
  void initState() {
    super.initState();
    _priceController = TextEditingController(text: widget.asset.currentPrice.toString());
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _priceController,
              decoration: const InputDecoration(
                labelText: 'New Price',
                prefixText: '₹ ',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton(
            onPressed: _updatePrice,
            child: const Text(AppStrings.update),
          ),
        ],
      ),
    );
  }

  Future<void> _updatePrice() async {
    final newPrice = double.tryParse(_priceController.text);
    if (newPrice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.errorInvalidNumber)),
      );
      return;
    }

    final repository = ref.read(assetRepositoryProvider);
    await repository.updateAssetPrice(widget.asset.id, newPrice);
    
    ref.invalidate(allAssetsProvider);
    ref.invalidate(portfolioSummaryProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Price updated successfully')),
      );
    }
  }
}
