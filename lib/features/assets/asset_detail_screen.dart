import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/asset.dart';
import '../../data/models/asset_type.dart';
import '../../services/gold_price_service.dart';
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
                          color: asset.type.color.withValues(alpha: 0.15),
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
                      color: color.withValues(alpha: 0.15),
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
                  _buildDetailRow(
                    'Quantity',
                    '${CurrencyFormatter.formatQuantity(asset.quantity)} ${asset.type.unitLabel}'.trim(),
                  ),
                  _buildDivider(),
                  _buildDetailRow('Purchase Price', CurrencyFormatter.formatINR(asset.purchasePrice)),
                  _buildDivider(),
                  _buildDetailRow('Current Price', CurrencyFormatter.formatINR(asset.currentPrice)),
                  _buildDivider(),
                  _buildDetailRow('Total Invested', CurrencyFormatter.formatINR(asset.totalInvested)),
                  _buildDivider(),
                  _buildDetailRow(
                    'Purchase Date',
                    '${asset.purchaseDate.day}/${asset.purchaseDate.month}/${asset.purchaseDate.year}',
                  ),
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
    final navigator = Navigator.of(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddAssetScreen(existingAsset: asset),
      ),
    ).then((_) {
      ref.invalidate(allAssetsProvider);
      navigator.pop();
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
  bool _isFetchingLivePrice = false;
  GoldPriceBreakdown? _lastBreakdown;
  String? _fetchError;

  @override
  void initState() {
    super.initState();
    _priceController = TextEditingController(
      text: widget.asset.currentPrice.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  bool get _isGold => widget.asset.type == AssetType.gold;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Live fetch button for gold assets
        if (_isGold) ...[
          _buildGoldLivePriceCard(context),
          const SizedBox(height: 12),
        ],

        // Manual price update card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isGold)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Or enter price manually:',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _priceController,
                      decoration: const InputDecoration(
                        labelText: 'Price per gram',
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
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGoldLivePriceCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFFD700).withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: Color(0xFFFFD700), size: 18),
              const SizedBox(width: 8),
              Text(
                'Live Gold Price (COMEX → INR/gram)',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_fetchError != null)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: AppColors.error, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _fetchError!,
                      style: TextStyle(color: AppColors.error, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

          if (_lastBreakdown != null) ...[
            _buildBreakdownRow('COMEX (GC=F)', '\$${_lastBreakdown!.usdPerTroyOz.toStringAsFixed(2)}/troy oz'),
            _buildBreakdownRow('USD/gram', '\$${_lastBreakdown!.usdPerGram.toStringAsFixed(4)}'),
            _buildBreakdownRow(
              'Forex rate',
              '1 USD = ₹${_lastBreakdown!.forexRate.toStringAsFixed(2)}${_lastBreakdown!.usedLiveForex ? ' (live)' : ' (approx)'}',
            ),
            _buildBreakdownRow('Base price', '₹${_lastBreakdown!.basePerGram.toStringAsFixed(2)}/gram'),
            _buildBreakdownRow(
              'Import Duty + AIDC',
              '${((_lastBreakdown!.importDutyRate + _lastBreakdown!.aidcRate) * 100).toStringAsFixed(0)}%',
            ),
            _buildBreakdownRow('GST', '${(_lastBreakdown!.gstRate * 100).toStringAsFixed(0)}%'),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Final price (incl. taxes)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '₹${_lastBreakdown!.finalPerGram.toStringAsFixed(2)}/gram',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFD700),
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _applyLivePrice(_lastBreakdown!.finalPerGram),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text(
                  'Apply ₹${_lastBreakdown!.finalPerGram.toStringAsFixed(2)}/gram',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  foregroundColor: Colors.black,
                ),
              ),
            ),
          ],

          if (_lastBreakdown == null && _fetchError == null)
            Text(
              'Fetches COMEX gold futures (GC=F), converts to INR/gram\nwith live forex + Indian import duty (10%) + AIDC (5%) + GST (3%)',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),

          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isFetchingLivePrice ? null : _fetchLiveGoldPrice,
              icon: _isFetchingLivePrice
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: Text(
                _isFetchingLivePrice
                    ? 'Fetching from COMEX...'
                    : (_lastBreakdown != null ? 'Refresh Live Price' : 'Fetch Live Price'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchLiveGoldPrice() async {
    setState(() {
      _isFetchingLivePrice = true;
      _fetchError = null;
    });

    try {
      final goldService = ref.read(goldPriceServiceProvider);
      final targetCurrency = widget.asset.currency.isNotEmpty
          ? widget.asset.currency
          : 'INR';

      final breakdown = await goldService.fetchGoldPriceBreakdown(
        targetCurrency: targetCurrency,
      );

      if (!mounted) return;

      if (breakdown == null) {
        setState(() {
          _fetchError =
              'Could not fetch gold price from COMEX (GC=F).\nCheck your internet connection.';
          _isFetchingLivePrice = false;
        });
        return;
      }

      setState(() {
        _lastBreakdown = breakdown;
        _isFetchingLivePrice = false;
        _fetchError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fetchError = 'Error: $e';
        _isFetchingLivePrice = false;
      });
    }
  }

  Future<void> _applyLivePrice(double price) async {
    _priceController.text = price.toStringAsFixed(2);
    await _updatePrice(showSnackbar: false);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Gold price updated to ₹${price.toStringAsFixed(2)}/gram (incl. Indian taxes)',
        ),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<void> _updatePrice({bool showSnackbar = true}) async {
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

    if (showSnackbar && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Price updated successfully')),
      );
    }
  }
}
