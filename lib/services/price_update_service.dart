import '../data/models/asset.dart';
import '../data/models/asset_type.dart';
import '../data/repositories/asset_repository.dart';
import 'coingecko_service.dart';
import 'currency_converter_service.dart';
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
/// Converts prices to the asset's stored currency automatically.
class PriceUpdateService {
  final AssetRepository _assetRepository;
  final YahooFinanceService _yahooService;
  final CurrencyConverterService _currencyConverter;

  PriceUpdateService({
    required AssetRepository assetRepository,
    YahooFinanceService? yahooService,
    CurrencyConverterService? currencyConverter,
  })  : _assetRepository = assetRepository,
        _yahooService = yahooService ?? YahooFinanceService(),
        _currencyConverter = currencyConverter ?? CurrencyConverterService();

  /// Refresh prices for all assets that have a symbol or auto-trackable type.
  /// Returns a summary of the operation.
  Future<PriceRefreshResult> refreshAllPrices() async {
    final assets = _assetRepository.getAllAssets();
    final baseCurrency = _assetRepository.getBaseCurrency();
    final trackable = assets
        .where((a) => _isTrackable(a, baseCurrency: baseCurrency))
        .toList();

    int updated = 0;
    int skipped = assets.length - trackable.length;
    int failed = 0;
    final errors = <String>[];

    // Pre-fetch exchange rates once (shared across all conversions this session)
    final exchangeRates = await _currencyConverter.fetchRates();

    // Batch crypto assets into one CoinGecko call (efficient)
    final cryptoAssets =
        trackable.where((a) => a.type == AssetType.crypto).toList();
    final goldAssets =
        trackable.where((a) => a.type == AssetType.gold).toList();
    final otherAssets = trackable
        .where((a) => a.type != AssetType.crypto && a.type != AssetType.gold)
        .toList();

    // --- Handle crypto (batched via CoinGecko) ---
    // CoinGecko returns prices in the requested vs_currency.
    // We request in the asset's currency or base currency.
    if (cryptoAssets.isNotEmpty) {
      final symbols = cryptoAssets
          .map((a) => _getSymbol(a))
          .where((s) => s != null)
          .cast<String>()
          .toList();

      // Request crypto prices in base currency (e.g. INR or USD)
      final cryptoService =
          CoinGeckoService(vsCurrency: baseCurrency.toLowerCase());
      final results = await cryptoService.fetchMultiplePrices(symbols);

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

    // --- Handle gold ---
    // Two cases:
    // 1. MCX symbol (GOLDM.MCX) → returns INR per 10g → divide by 10 for per gram
    // 2. COMEX symbol (GC=F)    → returns USD per troy oz → convert to target/gram
    for (final asset in goldAssets) {
      final symbol = _getSymbol(asset, baseCurrency: baseCurrency);
      if (symbol == null) {
        skipped++;
        continue;
      }

      final result = await _yahooService.fetchPrice(symbol);
      if (result.success) {
        final targetCurrency =
            asset.currency.isNotEmpty ? asset.currency : baseCurrency;
        double pricePerGram;

        if (PriceSymbols.isMCXSymbol(symbol)) {
          // MCX Gold returns INR per 10 grams → convert to per gram
          // No forex conversion needed — already in INR
          pricePerGram = result.price / 10.0;
        } else {
          // COMEX GC=F returns USD per troy oz
          // Convert: USD/oz → target currency/gram
          if (exchangeRates.success) {
            pricePerGram =
                await _currencyConverter.goldUSDPerOzToTargetPerGram(
              result.price,
              targetCurrency,
            );
          } else {
            pricePerGram =
                await _currencyConverter.goldUSDPerOzToTargetPerGram(
              result.price,
              targetCurrency,
            );
            errors.add(
                'Warning: using approximate forex rates for ${asset.name}');
          }
        }

        await _assetRepository.updateAssetPrice(asset.id, pricePerGram);
        updated++;
      } else {
        failed++;
        errors.add('${asset.name} ($symbol): ${result.error}');
      }

      await Future.delayed(const Duration(milliseconds: 300));
    }

    // --- Handle stocks, bonds (Yahoo Finance, may return in USD or local currency) ---
    for (final asset in otherAssets) {
      final symbol = _getSymbol(asset);
      if (symbol == null) {
        skipped++;
        continue;
      }

      final result = await _yahooService.fetchPrice(symbol);
      if (result.success) {
        double price = result.price;
        final assetCurrency =
            asset.currency.isNotEmpty ? asset.currency : baseCurrency;

        // If Yahoo returns USD but asset is stored in a different currency, convert
        if (result.currency == 'USD' &&
            assetCurrency != 'USD' &&
            exchangeRates.success) {
          price = exchangeRates.convert(price, assetCurrency);
        }

        await _assetRepository.updateAssetPrice(asset.id, price);
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

  /// Refresh price for a single asset with proper currency conversion
  Future<PriceResult> refreshSinglePrice(Asset asset) async {
    final baseCurrency = _assetRepository.getBaseCurrency();
    final symbol = _getSymbol(asset);

    if (symbol == null) {
      return PriceResult.failure(
        asset.name,
        'No symbol set for ${asset.type.displayName} asset "${asset.name}"',
      );
    }

    if (asset.type == AssetType.crypto) {
      // CoinGecko: request in asset's own currency
      final targetCurrency =
          asset.currency.isNotEmpty ? asset.currency : baseCurrency;
      final cryptoService =
          CoinGeckoService(vsCurrency: targetCurrency.toLowerCase());
      final result = await cryptoService.fetchPrice(symbol);

      if (result.success) {
        await _assetRepository.updateAssetPrice(asset.id, result.price);
      }
      return result;
    }

    if (asset.type == AssetType.gold) {
      final goldSymbol = _getSymbol(asset, baseCurrency: baseCurrency);
      if (goldSymbol == null) {
        return PriceResult.failure(asset.name, 'No gold symbol available');
      }
      final result = await _yahooService.fetchPrice(goldSymbol);
      if (!result.success) return result;

      final targetCurrency =
          asset.currency.isNotEmpty ? asset.currency : baseCurrency;
      double pricePerGram;

      if (PriceSymbols.isMCXSymbol(goldSymbol)) {
        // MCX: INR per 10g → per gram
        pricePerGram = result.price / 10.0;
      } else {
        // COMEX: USD/troy oz → targetCurrency/gram
        pricePerGram = await _currencyConverter.goldUSDPerOzToTargetPerGram(
          result.price,
          targetCurrency,
        );
      }

      await _assetRepository.updateAssetPrice(asset.id, pricePerGram);
      return PriceResult(
        symbol: goldSymbol,
        price: pricePerGram,
        currency: targetCurrency,
        fetchedAt: DateTime.now(),
        success: true,
      );
    }

    // Stocks/bonds
    final result = await _yahooService.fetchPrice(symbol);
    if (result.success) {
      double price = result.price;
      final assetCurrency =
          asset.currency.isNotEmpty ? asset.currency : baseCurrency;

      if (result.currency == 'USD' && assetCurrency != 'USD') {
        final rates = await _currencyConverter.fetchRates();
        if (rates.success) {
          price = rates.convert(price, assetCurrency);
        }
      }

      await _assetRepository.updateAssetPrice(asset.id, price);
      return PriceResult(
        symbol: symbol,
        price: price,
        currency: assetCurrency,
        fetchedAt: DateTime.now(),
        success: true,
      );
    }

    return result;
  }

  /// Determines if an asset can be auto-tracked
  bool _isTrackable(Asset asset, {String baseCurrency = 'INR'}) {
    if (!PriceSymbols.supportsAutoTracking(asset.type)) return false;
    return _getSymbol(asset, baseCurrency: baseCurrency) != null;
  }

  /// Gets the effective symbol for an asset (user-set or auto-default).
  /// [baseCurrency] is used to pick the best gold source when no symbol is set.
  String? _getSymbol(Asset asset, {String baseCurrency = 'INR'}) {
    final userSymbol = asset.symbol?.trim();
    if (userSymbol != null && userSymbol.isNotEmpty) return userSymbol;
    return PriceSymbols.defaultSymbol(asset.type, baseCurrency: baseCurrency);
  }
}
