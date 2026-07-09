import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_theme.dart';
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
    final gainColor =
        isProfit ? AppColors.gainOn(context) : AppColors.lossOn(context);
    final unit = asset.type.unitLabel;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header: back + gradient avatar + name + live pill ──────────
              _Header(asset: asset),

              const SizedBox(height: 16),

              // ── Current value card with sparkline + range selector ─────────
              _ValueCard(
                asset: asset,
                isProfit: isProfit,
                gainColor: gainColor,
              ),

              const SizedBox(height: 14),

              // ── 2-column soft stat grid ────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      label: 'HOLDING',
                      value:
                          '${CurrencyFormatter.formatQuantity(asset.quantity)}${unit.isNotEmpty ? ' $unit' : ''}',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatTile(
                      label: 'AVG BUY',
                      value: CurrencyFormatter.formatINR(asset.purchasePrice),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      label: 'CURRENT',
                      value: CurrencyFormatter.formatINR(asset.currentPrice),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatTile(
                      label: 'INVESTED',
                      value: CurrencyFormatter.formatINR(asset.totalInvested),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // ── Extra detail rows (date / platform / currency) ─────────────
              _DetailsCard(asset: asset),

              if (asset.notes != null && asset.notes!.isNotEmpty) ...[
                const SizedBox(height: 14),
                _SectionLabel(AppStrings.notes),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    boxShadow: AppShadows.soft(opacity: 0.14, y: 10, blur: 24),
                  ),
                  child: Text(
                    asset.notes!,
                    style: AppTheme.body(
                      size: 13.5,
                      color: AppColors.textSecondaryOn(context),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // ── Update price ───────────────────────────────────────────────
              _SectionLabel(AppStrings.updatePrices),
              const SizedBox(height: 10),
              _UpdatePriceCard(asset: asset),

              const SizedBox(height: 18),

              // ── Bottom actions: Edit (gradient) + Delete (soft) ────────────
              Row(
                children: [
                  Expanded(
                    child: _GradientButton(
                      label: 'Edit',
                      icon: Icons.edit_rounded,
                      onTap: () => _editAsset(context, ref),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SoftButton(
                      label: 'Delete',
                      icon: Icons.delete_outline_rounded,
                      color: AppColors.lossOn(context),
                      onTap: () => _confirmDelete(context, ref),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete asset?'),
        content: Text(
          'This will permanently remove "${asset.name}" from your portfolio.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              Navigator.pop(dialogContext);
              await ref
                  .read(portfolioWriteServiceProvider)
                  .deleteAssetWithTransactions(asset.id);
              ref.invalidate(allAssetsProvider);
              ref.invalidate(portfolioSummaryProvider);
              navigator.pop();
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.lossOn(context),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final Asset asset;
  const _Header({required this.asset});

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Row(
      children: [
        // Back button — soft surface square.
        Material(
          color: surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.avatar),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).maybePop(),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                Icons.chevron_left_rounded,
                size: 24,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Gradient type avatar.
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: softAvatarGradient(asset.type.color),
            borderRadius: BorderRadius.circular(AppRadii.avatar),
            boxShadow: AppShadows.glow(asset.type.color, opacity: 0.4),
          ),
          child: Icon(asset.type.icon, color: Colors.white, size: 19),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                asset.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.heading(
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              Text(
                asset.symbol ?? asset.type.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(
                  size: 11.5,
                  weight: FontWeight.w700,
                  color: asset.type.color,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Price freshness — the real fact from priceUpdatedAt (prices only
        // change on manual refresh, so no "live" indicator).
        if (_priceAge(asset) != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(AppRadii.pill),
              boxShadow: AppShadows.soft(opacity: 0.12, y: 6, blur: 14),
            ),
            child: Text(
              'Updated ${_priceAge(asset)}',
              style: AppTheme.body(
                size: 11,
                weight: FontWeight.w700,
                color: AppColors.textSecondaryOn(context),
              ),
            ),
          ),
      ],
    );
  }
}

/// Relative age of the asset's last price update, or null when never fetched.
/// Mirrors the wording used on the assets list tiles.
String? _priceAge(Asset asset) {
  if (asset.priceUpdatedAt == null) return null;
  final diff = DateTime.now().difference(asset.priceUpdatedAt!);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${(diff.inDays / 7).floor()}w ago';
}

/// Singular unit for the manual price label ('gram', 'coin', 'unit').
String _priceUnit(AssetType type) {
  final label = type.unitLabel; // 'units', 'grams', 'coins', or ''
  if (label.isEmpty) return 'unit';
  return label.endsWith('s') ? label.substring(0, label.length - 1) : label;
}

// ─────────────────────────────────────────────────────────────────────────────
// Value card
// ─────────────────────────────────────────────────────────────────────────────

class _ValueCard extends StatelessWidget {
  final Asset asset;
  final bool isProfit;
  final Color gainColor;

  const _ValueCard({
    required this.asset,
    required this.isProfit,
    required this.gainColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.hero),
        boxShadow: AppShadows.soft(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current value',
            style: AppTheme.body(
              size: 12,
              weight: FontWeight.w700,
              color: AppColors.textSecondaryOn(context),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  CurrencyFormatter.formatINR(asset.currentValue),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.heading(
                    size: 30,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  '${isProfit ? '▲' : '▼'} ${CurrencyFormatter.formatPercentage(asset.gainLossPercentage.abs(), showSign: false)}',
                  style: AppTheme.body(
                    size: 13,
                    weight: FontWeight.w800,
                    color: gainColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 1),
          Text(
            '${isProfit ? '+' : '-'}${CurrencyFormatter.formatINR(asset.gainLoss.abs())} since you bought',
            style: AppTheme.body(
              size: 12,
              weight: FontWeight.w600,
              color: AppColors.textSecondaryOn(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stat tile
// ─────────────────────────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  final String label;
  final String value;

  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.small),
        boxShadow: AppShadows.soft(opacity: 0.12, y: 8, blur: 20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTheme.body(
              size: 10,
              weight: FontWeight.w800,
              color: AppColors.textSecondaryOn(context),
            ).copyWith(letterSpacing: 0.3),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.heading(
              size: 16,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Details card
// ─────────────────────────────────────────────────────────────────────────────

class _DetailsCard extends StatelessWidget {
  final Asset asset;
  const _DetailsCard({required this.asset});

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      (
        'Purchase date',
        '${asset.purchaseDate.day}/${asset.purchaseDate.month}/${asset.purchaseDate.year}',
      ),
      if (asset.platform != null) ('Platform', asset.platform!),
      if (asset.currency != 'INR') ('Currency', asset.currency),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: AppShadows.soft(opacity: 0.14, y: 10, blur: 24),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                color: Theme.of(context).colorScheme.outline,
                height: 1,
                indent: 16,
                endIndent: 16,
              ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    rows[i].$1,
                    style: AppTheme.body(
                      size: 13.5,
                      color: AppColors.textSecondaryOn(context),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      rows[i].$2,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(
                        size: 13.5,
                        weight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small bits
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(text, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _GradientButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(AppRadii.tile),
        boxShadow: AppShadows.glow(AppColors.primary, opacity: 0.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.tile),
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 19),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppTheme.heading(size: 15, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoftButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SoftButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.tile),
        boxShadow: AppShadows.soft(opacity: 0.14, y: 10, blur: 22),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.tile),
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 19),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppTheme.heading(size: 15, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Update price (gold live fetch + manual) — restyled, behaviour preserved
// ─────────────────────────────────────────────────────────────────────────────

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
        // Live fetch card for gold assets
        if (_isGold) ...[
          _buildGoldLivePriceCard(context),
          const SizedBox(height: 12),
        ],

        // Manual price update card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadii.card),
            boxShadow: AppShadows.soft(opacity: 0.14, y: 10, blur: 24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _priceController,
                      decoration: InputDecoration(
                        labelText: 'Price per ${_priceUnit(widget.asset.type)}',
                        prefixText:
                            '${AppConstants.currencies[widget.asset.currency] ?? widget.asset.currency} ',
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _UpdateButton(onTap: _updatePrice),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGoldLivePriceCard(BuildContext context) {
    final goldTone = AppColors.goldColor;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: AppShadows.soft(opacity: 0.14, y: 10, blur: 24),
        border: Border.all(
          color: goldTone.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: goldTone, size: 18),
              const SizedBox(width: 8),
              Text(
                'Live Gold Price',
                style: AppTheme.body(
                  size: 14,
                  weight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_fetchError != null)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.lossOn(context).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadii.small),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                      color: AppColors.lossOn(context), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Could not fetch live price. Check your connection.',
                      style: AppTheme.body(
                        size: 12,
                        color: AppColors.lossOn(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          if (_lastBreakdown != null) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Current price per gram',
                  style: AppTheme.body(
                    size: 14,
                    color: AppColors.textSecondaryOn(context),
                  ),
                ),
                Text(
                  '₹${_lastBreakdown!.finalPerGram.toStringAsFixed(2)}',
                  style: AppTheme.heading(size: 18, color: goldTone),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () =>
                    _applyLivePrice(_lastBreakdown!.finalPerGram),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Apply Live Price'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: goldTone,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],

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
                    ? 'Fetching...'
                    : (_lastBreakdown != null
                        ? 'Refresh Price'
                        : 'Fetch Live Price'),
              ),
            ),
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
      final targetCurrency =
          widget.asset.currency.isNotEmpty ? widget.asset.currency : 'INR';

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

/// Small gradient "Update" CTA matching the soft-pop direction.
class _UpdateButton extends StatelessWidget {
  final VoidCallback onTap;
  const _UpdateButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(AppRadii.tile),
        boxShadow: AppShadows.glow(AppColors.primary, opacity: 0.45),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.tile),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Center(
              child: Text(
                AppStrings.update,
                style: AppTheme.heading(size: 14, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
