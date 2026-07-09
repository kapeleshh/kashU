import 'asset.dart';
import 'asset_type.dart';

/// Model representing a summary of the portfolio
class PortfolioSummary {
  final double totalValue;
  final double totalInvested;
  final double totalGainLoss;
  final double totalGainLossPercentage;
  final double todaysChange;
  final double todaysChangePercentage;

  /// True only when there is a prior-day snapshot to compare against, so the
  /// UI can hide the "today" figure until day-over-day data actually exists.
  final bool hasTodaysChange;
  final Map<AssetType, double> assetAllocation;
  final List<Asset> topGainers;
  final List<Asset> topLosers;
  final int totalAssets;
  final DateTime? lastUpdated;

  PortfolioSummary({
    required this.totalValue,
    required this.totalInvested,
    required this.totalGainLoss,
    required this.totalGainLossPercentage,
    required this.todaysChange,
    required this.todaysChangePercentage,
    this.hasTodaysChange = false,
    required this.assetAllocation,
    required this.topGainers,
    required this.topLosers,
    required this.totalAssets,
    this.lastUpdated,
  });

  factory PortfolioSummary.empty() {
    return PortfolioSummary(
      totalValue: 0,
      totalInvested: 0,
      totalGainLoss: 0,
      totalGainLossPercentage: 0,
      todaysChange: 0,
      todaysChangePercentage: 0,
      assetAllocation: {},
      topGainers: [],
      topLosers: [],
      totalAssets: 0,
    );
  }

  bool get isEmpty => totalAssets == 0;
  bool get isProfit => totalGainLoss >= 0;
}
