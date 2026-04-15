import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/asset.dart';
import '../../data/models/portfolio_summary.dart';
import '../../data/repositories/asset_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../services/currency_converter_service.dart';
import '../../services/gold_price_service.dart';
import '../../services/price_update_service.dart';

/// Provider for AssetRepository
final assetRepositoryProvider = Provider<AssetRepository>((ref) {
  return AssetRepository();
});

/// Provider for TransactionRepository
final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  return TransactionRepository();
});

/// Provider for base currency (persisted in settings)
final baseCurrencyProvider = StateProvider<String>((ref) {
  final repo = ref.watch(assetRepositoryProvider);
  return repo.getBaseCurrency();
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
    todaysChange: 0,
    todaysChangePercentage: 0,
    assetAllocation: repository.getAssetAllocation(),
    topGainers: repository.getTopGainers(),
    topLosers: repository.getTopLosers(),
    totalAssets: assets.length,
    lastUpdated: DateTime.now(),
  );
});

/// Provider for all assets - correctly typed as `List<Asset>`
final allAssetsProvider = Provider<List<Asset>>((ref) {
  final repository = ref.watch(assetRepositoryProvider);
  return repository.getAllAssets();
});

/// Provider for CurrencyConverterService (singleton with cache)
final currencyConverterServiceProvider =
    Provider<CurrencyConverterService>((ref) {
  return CurrencyConverterService();
});

/// Provider for GoldPriceService (uses COMEX GC=F + live forex + Indian taxes)
final goldPriceServiceProvider = Provider<GoldPriceService>((ref) {
  final currencyConverter = ref.watch(currencyConverterServiceProvider);
  return GoldPriceService(currencyConverter: currencyConverter);
});

/// Provider for PriceUpdateService (includes currency conversion + gold tax)
final priceUpdateServiceProvider = Provider<PriceUpdateService>((ref) {
  final assetRepo = ref.watch(assetRepositoryProvider);
  final currencyConverter = ref.watch(currencyConverterServiceProvider);
  final goldPriceService = ref.watch(goldPriceServiceProvider);
  return PriceUpdateService(
    assetRepository: assetRepo,
    currencyConverter: currencyConverter,
    goldPriceService: goldPriceService,
  );
});

/// Tracks whether a price refresh is currently in progress
final isRefreshingPricesProvider = StateProvider<bool>((ref) => false);

/// Holds the result of the last price refresh (null if never refreshed)
final lastRefreshResultProvider =
    StateProvider<PriceRefreshResult?>((ref) => null);

/// Threshold after which prices are considered stale and a warning is shown.
const Duration stalePriceThreshold = Duration(hours: 4);

/// True when prices haven't been refreshed for [stalePriceThreshold] or longer.
///
/// Reads the persisted last-refresh timestamp from the settings box so the
/// warning survives app restarts.
final isPriceStaleProvider = Provider<bool>((ref) {
  // Also invalidated after a fresh refresh so the banner clears immediately.
  final lastResult = ref.watch(lastRefreshResultProvider);
  if (lastResult != null) {
    return DateTime.now().difference(lastResult.completedAt) >
        stalePriceThreshold;
  }

  final settings = Hive.box(AppConstants.settingsBox);
  final raw = settings.get('lastPriceRefreshAt') as String?;
  if (raw == null) return false; // no history → don't nag on first open
  final savedAt = DateTime.tryParse(raw);
  if (savedAt == null) return false;
  return DateTime.now().difference(savedAt) > stalePriceThreshold;
});
