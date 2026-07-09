import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/asset.dart';
import '../../data/models/asset_type.dart';
import '../../services/currency_converter_service.dart';
import '../../shared/providers/portfolio_provider.dart';
import 'add_asset_screen.dart';
import 'asset_detail_screen.dart';

class AssetsScreen extends ConsumerStatefulWidget {
  const AssetsScreen({super.key});

  @override
  ConsumerState<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends ConsumerState<AssetsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  AssetType? _selectedFilter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assets = ref.watch(allAssetsProvider);
    final base = ref.watch(baseCurrencyProvider);
    final rates = ref.watch(exchangeRatesProvider).valueOrNull ??
        ExchangeRateResult.failure('loading');
    final totalValue = assets.fold<double>(
      0,
      (sum, a) => sum +
          rates.convertBetween(
              a.currentValue, a.currency.isEmpty ? base : a.currency, base),
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(
              count: assets.length,
              totalValue: totalValue,
              baseCurrency: base,
            ),
            _TypeTabBar(controller: _tabController),
            if (assets.isNotEmpty) ...[
              const SizedBox(height: 6),
              _FilterPills(
                selected: _selectedFilter,
                onSelected: (t) => setState(() => _selectedFilter = t),
              ),
            ],
            Expanded(
              child: assets.isEmpty
                  ? _buildEmptyState()
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildAssetsByType(assets, rates, base),
                        _buildAssetsByPlatform(assets, rates, base),
                      ],
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton:
          assets.isEmpty ? null : _SoftFab(onTap: _navigateToAddAsset),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(AppRadii.card),
                boxShadow: AppShadows.glow(AppColors.primary, opacity: 0.45),
              ),
              child: const Icon(
                Icons.account_balance_wallet_rounded,
                size: 42,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              AppStrings.noAssets,
              textAlign: TextAlign.center,
              style: AppTheme.heading(
                size: 18,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add your first holding to start tracking',
              textAlign: TextAlign.center,
              style: AppTheme.body(
                size: 13,
                weight: FontWeight.w600,
                color: AppColors.textSecondaryOn(context),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _navigateToAddAsset,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add your first asset'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssetsByType(
      List<Asset> assets, ExchangeRateResult rates, String base) {
    final groupedAssets = <AssetType, List<Asset>>{};

    for (final asset in assets) {
      if (_selectedFilter != null && asset.type != _selectedFilter) continue;
      groupedAssets.putIfAbsent(asset.type, () => []).add(asset);
    }

    if (groupedAssets.isEmpty) {
      return _buildFilterEmpty();
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      itemCount: groupedAssets.length,
      itemBuilder: (context, index) {
        final type = groupedAssets.keys.elementAt(index);
        final typeAssets = groupedAssets[type]!;
        final totalValue = typeAssets.fold<double>(
          0,
          (sum, a) => sum +
              rates.convertBetween(
                  a.currentValue, a.currency.isEmpty ? base : a.currency, base),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _GroupHeader(
              gradient: softAvatarGradient(type.color),
              icon: type.icon,
              title: type.displayName,
              totalValue: totalValue,
              baseCurrency: base,
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < typeAssets.length; i++) ...[
              if (i > 0) const SizedBox(height: 9),
              _AssetTile(
                asset: typeAssets[i],
                valueInBase: rates.convertBetween(
                    typeAssets[i].currentValue,
                    typeAssets[i].currency.isEmpty
                        ? base
                        : typeAssets[i].currency,
                    base),
                baseCurrency: base,
                onTap: () => _navigateToAssetDetail(typeAssets[i]),
                priceAge: _priceAge(typeAssets[i]),
                // The group header already names the type.
                showType: false,
              ),
            ],
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Widget _buildAssetsByPlatform(
      List<Asset> assets, ExchangeRateResult rates, String base) {
    final groupedAssets = <String, List<Asset>>{};

    for (final asset in assets) {
      if (_selectedFilter != null && asset.type != _selectedFilter) continue;
      final platform = asset.platform ?? 'Other';
      groupedAssets.putIfAbsent(platform, () => []).add(asset);
    }

    if (groupedAssets.isEmpty) {
      return _buildFilterEmpty();
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      itemCount: groupedAssets.length,
      itemBuilder: (context, index) {
        final platform = groupedAssets.keys.elementAt(index);
        final platformAssets = groupedAssets[platform]!;
        final totalValue = platformAssets.fold<double>(
          0,
          (sum, a) => sum +
              rates.convertBetween(
                  a.currentValue, a.currency.isEmpty ? base : a.currency, base),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _GroupHeader(
              gradient: AppColors.primaryGradient,
              icon: Icons.account_balance_rounded,
              title: platform,
              totalValue: totalValue,
              baseCurrency: base,
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < platformAssets.length; i++) ...[
              if (i > 0) const SizedBox(height: 9),
              _AssetTile(
                asset: platformAssets[i],
                valueInBase: rates.convertBetween(
                    platformAssets[i].currentValue,
                    platformAssets[i].currency.isEmpty
                        ? base
                        : platformAssets[i].currency,
                    base),
                baseCurrency: base,
                onTap: () => _navigateToAssetDetail(platformAssets[i]),
                priceAge: _priceAge(platformAssets[i]),
              ),
            ],
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Widget _buildFilterEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No assets match the filter',
          style: AppTheme.body(
            size: 14,
            weight: FontWeight.w600,
            color: AppColors.textSecondaryOn(context),
          ),
        ),
      ),
    );
  }

  String? _priceAge(Asset asset) {
    if (asset.priceUpdatedAt == null) return null;
    final diff = DateTime.now().difference(asset.priceUpdatedAt!);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  void _navigateToAddAsset() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddAssetScreen()),
    ).then((_) => ref.invalidate(allAssetsProvider));
  }

  void _navigateToAssetDetail(Asset asset) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AssetDetailScreen(asset: asset)),
    ).then((_) => ref.invalidate(allAssetsProvider));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final int count;
  final double totalValue;
  final String baseCurrency;

  const _Header({
    required this.count,
    required this.totalValue,
    required this.baseCurrency,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = count == 0
        ? 'Nothing tracked yet'
        : '$count ${count == 1 ? 'holding' : 'holdings'} · '
            '${CurrencyFormatter.formatCompactCurrency(totalValue, baseCurrency)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.assets,
            style: AppTheme.heading(
              size: 22,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: AppTheme.body(
              size: 12.5,
              weight: FontWeight.w700,
              color: AppColors.textSecondaryOn(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab bar (By Type / By Platform)
// ─────────────────────────────────────────────────────────────────────────────

class _TypeTabBar extends StatelessWidget {
  final TabController controller;

  const _TypeTabBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.label,
        indicatorWeight: 3,
        dividerColor: Colors.transparent,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondaryOn(context),
        labelStyle: AppTheme.body(size: 14, weight: FontWeight.w800),
        unselectedLabelStyle: AppTheme.body(size: 14, weight: FontWeight.w700),
        tabs: const [
          Tab(text: 'By Type'),
          Tab(text: 'By Platform'),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter pills (All + per asset type) — restyled C·Soft chips
// ─────────────────────────────────────────────────────────────────────────────

class _FilterPills extends StatelessWidget {
  final AssetType? selected;
  final ValueChanged<AssetType?> onSelected;

  const _FilterPills({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _pill(context, label: 'All', active: selected == null, onTap: () {
            HapticFeedback.selectionClick();
            onSelected(null);
          }),
          for (final type in AssetType.values) ...[
            const SizedBox(width: 8),
            _pill(
              context,
              label: type.displayName,
              active: selected == type,
              onTap: () {
                HapticFeedback.selectionClick();
                onSelected(selected == type ? null : type);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _pill(
    BuildContext context, {
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          gradient: active ? AppColors.primaryGradient : null,
          color: active ? null : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          boxShadow: active
              ? AppShadows.glow(AppColors.primary, opacity: 0.4)
              : AppShadows.soft(opacity: 0.10, y: 6, blur: 14),
        ),
        child: Text(
          label,
          style: AppTheme.body(
            size: 11.5,
            weight: FontWeight.w800,
            color: active ? Colors.white : AppColors.textSecondaryOn(context),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Group header (By Type / By Platform sections)
// ─────────────────────────────────────────────────────────────────────────────

class _GroupHeader extends StatelessWidget {
  final Gradient gradient;
  final IconData icon;
  final String title;
  final double totalValue;
  final String baseCurrency;

  const _GroupHeader({
    required this.gradient,
    required this.icon,
    required this.title,
    required this.totalValue,
    required this.baseCurrency,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 17),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.heading(
                size: 15,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            CurrencyFormatter.formatCompactCurrency(totalValue, baseCurrency),
            style: AppTheme.heading(size: 14, color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Asset tile (soft card + gradient avatar) — matches top_performers_list.dart
// ─────────────────────────────────────────────────────────────────────────────

class _AssetTile extends StatelessWidget {
  final Asset asset;

  /// The asset's current value converted into the base currency for display.
  final double valueInBase;
  final String baseCurrency;
  final VoidCallback onTap;
  final String? priceAge;

  /// Whether the subtitle includes the asset type name. Off on the By-Type
  /// tab, where the group header already names the type.
  final bool showType;

  const _AssetTile({
    required this.asset,
    required this.valueInBase,
    required this.baseCurrency,
    required this.onTap,
    required this.priceAge,
    this.showType = true,
  });

  @override
  Widget build(BuildContext context) {
    final isProfit = asset.gainLossPercentage >= 0;
    final changeColor =
        isProfit ? AppColors.gainOn(context) : AppColors.lossOn(context);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadii.tile),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.tile),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadii.tile),
            boxShadow: AppShadows.soft(opacity: 0.16, y: 10, blur: 24),
          ),
          child: Row(
            children: [
              _avatar(),
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
                    if (_subtitle().isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        _subtitle(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(
                          size: 11,
                          weight: FontWeight.w600,
                          color: AppColors.textSecondaryOn(context),
                        ),
                      ),
                    ],
                    if (priceAge != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        'Price · $priceAge',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(
                          size: 10,
                          weight: FontWeight.w600,
                          color: AppColors.textTertiaryOn(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.formatCurrency(valueInBase, baseCurrency),
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
        ),
      ),
    );
  }

  Widget _avatar() {
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: softAvatarGradient(asset.type.color),
        borderRadius: BorderRadius.circular(AppRadii.avatar),
      ),
      child: Text(
        _initials(),
        style: AppTheme.heading(size: 14, color: Colors.white),
      ),
    );
  }

  String _initials() {
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

  String _subtitle() {
    final unit = asset.type.unitLabel;
    final qty = CurrencyFormatter.formatQuantity(asset.quantity);
    final qtyPart = unit.isEmpty ? '' : '$qty $unit';
    if (!showType) return qtyPart;
    if (qtyPart.isEmpty) return asset.type.displayName;
    return '$qtyPart · ${asset.type.displayName}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mint gradient FAB — matches the dashboard's _SoftFab
// ─────────────────────────────────────────────────────────────────────────────

class _SoftFab extends StatelessWidget {
  final VoidCallback onTap;
  const _SoftFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        gradient: AppColors.mintGradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.glow(const Color(0xFF10B981), opacity: 0.6),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}
