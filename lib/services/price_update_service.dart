import '../data/models/asset.dart';
import '../data/models/asset_type.dart';
import '../data/repositories/asset_repository.dart';
import 'coingecko_service.dart';
import 'price_service.dart';
import 'yahoo_finance_service.dart';

/// Summary of a bulk price refresh operation
class PriceRefreshResult {
  final int total;
  final int updated;
  final int skipped;
  final int failed;
  final List<String> errors;
  final DateTime completedAt;

  const PriceRefreshResult({
    required this.total,
    required this.updated,
    required this.skipped,
    required this.failed,
    required this.errors,
    required this.completedAt,
  });

  bool get hasErrors => errors.isNotEmpty;

  String get summary =>
      'Updated $updated/$total assets${failed > 0 ? ', $failed failed' : ''}';
}

/// Orchestrates price updates for all assets in the portfolio.
/// Routes each asset to the correct API based on AssetType.
class PriceUpdateService {
  final AssetRepository _assetRepository;
  final YahooFinanceService _yahooService;
  final CoinGeckoService _coinGeckoService;

  PriceUpdateService({
    required AssetRepository assetRepository,
    YahooFinanceService? yahooService,
    CoinGeckoService? coinGeckoService,
  })  : _assetRepository = assetRepository,
        _yahooService = yahooService ?? YahooFinanceService(),
        _coinGeckoService = coinGeckoService ?? CoinGeckoService();

  /// Refresh prices for all assets that have a symbol or auto-trackable type.
  /// Returns a summary of the operation.
  Future<PriceRefreshResult> refreshAllPrices() async {
    final assets = _assetRepository.getAllAssets();
    final trackable = assets.where(_isTrackable).toList();

    int updated = 0;
    int skipped = assets.length - trackable.length;
    int failed = 0;
    final errors = <String>[];

    // Batch crypto assets into one CoinGecko call (efficient)
    final cryptoAssets =
        trackable.where((a) => a.type == AssetType.crypto).toList();
    final nonCryptoAssets =
        trackable.where((a) => a.type != AssetType.crypto).toList();

    // --- Handle crypto (batched) ---
    if (cryptoAssets.isNotEmpty) {
      final symbols = cryptoAssets
          .map((a) => _getSymbol(a))
          .where((s) => s != null)
          .cast<String>()
          .toList();

      final results = await _coinGeckoService.fetchMultiplePrices(symbols);

      for (int i = 0; i < cryptoAssets.length; i++) {
        final asset = cryptoAssets[i];
        if (i >= results.length) break;
        final result = results[i];

        if (result.success) {
          await _assetRepository.updateAssetPrice(asset.id, result.price);
          updated++;
        } else {
          failed++;
          errors.add('${asset.name}: ${result.error}');
        }
      }
    }

    // --- Handle stocks, gold, bonds (individual calls via Yahoo Finance) ---
    for (final asset in nonCryptoAssets) {
      final symbol = _getSymbol(asset);
      if (symbol == null) {
        skipped++;
        continue;
      }

      final result = await _yahooService.fetchPrice(symbol);
      if (result.success) {
        await _assetRepository.updateAssetPrice(asset.id, result.price);
        updated++;
      } else {
        failed++;
        errors.add('${asset.name} ($symbol): ${result.error}');
      }

      // Small delay between Yahoo Finance calls to avoid rate limiting
      await Future.delayed(const Duration(milliseconds: 300));
    }

    return PriceRefreshResult(
      total: assets.length,
      updated: updated,
      skipped: skipped,
      failed: failed,
      errors: errors,
      completedAt: DateTime.now(),
    );
  }

  /// Refresh price for a single asset
  Future<PriceResult> refreshSinglePrice(Asset asset) async {
    final symbol = _getSymbol(asset);
    if (symbol == null) {
      return PriceResult.failure(
        asset.name,
        'No symbol set for ${asset.type.displayName} asset "${asset.name}"',
      );
    }

    PriceResult result;
    if (asset.type == AssetType.crypto) {
      result = await _coinGeckoService.fetchPrice(symbol);
    } else {
      result = await _yahooService.fetchPrice(symbol);
    }

    if (result.success) {
      await _assetRepository.updateAssetPrice(asset.id, result.price);
    }

    return result;
  }

  /// Determines if an asset can be auto-tracked
  bool _isTrackable(Asset asset) {
    if (!PriceSymbols.supportsAutoTracking(asset.type)) return false;
    return _getSymbol(asset) != null;
  }

  /// Gets the effective symbol for an asset (user-set or auto-default)
  String? _getSymbol(Asset asset) {
    final userSymbol = asset.symbol?.trim();
    if (userSymbol != null && userSymbol.isNotEmpty) return userSymbol;
    return PriceSymbols.defaultSymbol(asset.type);
  }
}
