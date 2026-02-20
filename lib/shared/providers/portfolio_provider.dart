import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/portfolio_summary.dart';
import '../../data/repositories/asset_repository.dart';

/// Provider for AssetRepository
final assetRepositoryProvider = Provider<AssetRepository>((ref) {
  return AssetRepository();
});

/// Provider for portfolio summary
final portfolioSummaryProvider = FutureProvider<PortfolioSummary>((ref) async {
  final repository = ref.watch(assetRepositoryProvider);
  
  final assets = repository.getAllAssets();
  
  if (assets.isEmpty) {
    return PortfolioSummary.empty();
  }

  final totalValue = repository.getTotalValue();
  final totalInvested = repository.getTotalInvested();
  final totalGainLoss = totalValue - totalInvested;
  final totalGainLossPercentage = totalInvested > 0 
      ? (totalGainLoss / totalInvested) * 100 
      : 0.0;

  return PortfolioSummary(
    totalValue: totalValue,
    totalInvested: totalInvested,
    totalGainLoss: totalGainLoss,
    totalGainLossPercentage: totalGainLossPercentage,
    todaysChange: 0, // TODO: Implement today's change tracking
    todaysChangePercentage: 0,
    assetAllocation: repository.getAssetAllocation(),
    topGainers: repository.getTopGainers(),
    topLosers: repository.getTopLosers(),
    totalAssets: assets.length,
    lastUpdated: DateTime.now(),
  );
});

/// Provider for all assets
final allAssetsProvider = Provider<List>((ref) {
  final repository = ref.watch(assetRepositoryProvider);
  return repository.getAllAssets();
});
