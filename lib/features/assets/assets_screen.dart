import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/asset.dart';
import '../../data/models/asset_type.dart';
import '../../shared/providers/portfolio_provider.dart';
import 'add_asset_screen.dart';
import 'asset_detail_screen.dart';

class AssetsScreen extends ConsumerStatefulWidget {
  const AssetsScreen({super.key});

  @override
  ConsumerState<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends ConsumerState<AssetsScreen> with SingleTickerProviderStateMixin {
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

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.assets),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'By Type'),
            Tab(text: 'By Platform'),
          ],
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _showFilterDialog(),
          ),
        ],
      ),
      body: assets.isEmpty
          ? _buildEmptyState()
          : TabBarView(
              controller: _tabController,
              children: [
                _buildAssetsByType(assets as List<Asset>),
                _buildAssetsByPlatform(assets),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToAddAsset(),
        icon: const Icon(Icons.add),
        label: const Text('Add Asset'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 80,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            AppStrings.noAssets,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _navigateToAddAsset(),
            icon: const Icon(Icons.add),
            label: const Text('Add Your First Asset'),
          ),
        ],
      ),
    );
  }

  Widget _buildAssetsByType(List<Asset> assets) {
    final groupedAssets = <AssetType, List<Asset>>{};
    
    for (final asset in assets) {
      if (_selectedFilter != null && asset.type != _selectedFilter) continue;
      groupedAssets.putIfAbsent(asset.type, () => []).add(asset);
    }

    if (groupedAssets.isEmpty) {
      return Center(
        child: Text(
          'No assets match the filter',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: groupedAssets.length,
      itemBuilder: (context, index) {
        final type = groupedAssets.keys.elementAt(index);
        final typeAssets = groupedAssets[type]!;
        final totalValue = typeAssets.fold(0.0, (sum, a) => sum + a.currentValue);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: type.color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(type.icon, color: type.color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      type.displayName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    CurrencyFormatter.formatCompactINR(totalValue),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            ...typeAssets.map((asset) => _buildAssetCard(asset)),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildAssetsByPlatform(List<Asset> assets) {
    final groupedAssets = <String, List<Asset>>{};
    
    for (final asset in assets) {
      final platform = asset.platform ?? 'Other';
      groupedAssets.putIfAbsent(platform, () => []).add(asset);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: groupedAssets.length,
      itemBuilder: (context, index) {
        final platform = groupedAssets.keys.elementAt(index);
        final platformAssets = groupedAssets[platform]!;
        final totalValue = platformAssets.fold(0.0, (sum, a) => sum + a.currentValue);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.account_balance, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      platform,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    CurrencyFormatter.formatCompactINR(totalValue),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            ...platformAssets.map((asset) => _buildAssetCard(asset)),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildAssetCard(Asset asset) {
    final isProfit = asset.gainLossPercentage >= 0;
    final color = isProfit ? AppColors.success : AppColors.error;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        onTap: () => _navigateToAssetDetail(asset),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: asset.type.color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            asset.type.icon,
            color: asset.type.color,
            size: 22,
          ),
        ),
        title: Text(
          asset.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          asset.symbol ?? '${CurrencyFormatter.formatQuantity(asset.quantity)} ${asset.type.unitLabel}'.trim(),
          style: TextStyle(color: AppColors.textTertiary),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              CurrencyFormatter.formatINR(asset.currentValue),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isProfit ? Icons.arrow_upward : Icons.arrow_downward,
                  color: color,
                  size: 14,
                ),
                Text(
                  CurrencyFormatter.formatPercentage(asset.gainLossPercentage.abs(), showSign: false),
                  style: TextStyle(color: color, fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Filter by Type',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    label: const Text('All'),
                    selected: _selectedFilter == null,
                    onSelected: (_) {
                      setState(() => _selectedFilter = null);
                      Navigator.pop(context);
                    },
                  ),
                  ...AssetType.values.map((type) {
                    return FilterChip(
                      avatar: Icon(type.icon, size: 18, color: type.color),
                      label: Text(type.displayName),
                      selected: _selectedFilter == type,
                      onSelected: (_) {
                        setState(() => _selectedFilter = type);
                        Navigator.pop(context);
                      },
                    );
                  }),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
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
