import '../data/models/asset.dart';
import '../data/models/asset_type.dart';
import '../data/repositories/asset_repository.dart';
import 'coingecko_service.dart';
import 'currency_converter_service.dart';
import 'gold_price_service.dart';
import 'price_cache_service.dart';
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
///
/// Gold price strategy:
///   1. Fetch COMEX GC=F (USD/troy oz) via Yahoo Finance — always reliable.
///   2. Convert USD/oz → USD/gram (÷ 31.1035).
///   3. Convert USD/gram → INR/gram via live forex (open.er-api.com).
///   4. Apply Indian taxes: BCD 5% + AIDC 1% + GST 3% ≈ 9.18% effective.
///
/// Cache strategy:
///   On a successful fetch the price is stored in [PriceCacheService].
///   On a failed fetch the last-known cached price (up to 30 min old) is
///   used as a fallback so the user always sees a value, never a blank.
class PriceUpdateService {
  final AssetRepository _assetRepository;
  final YahooFinanceService _yahooService;
  final CurrencyConverterService _currencyConverter;
  final GoldPriceService _goldPriceService;
  final PriceCacheService _priceCache;

  /// Optional factory for creating a [CoinGeckoService] with a specific
  /// vsCurrency. Injected in tests to avoid real HTTP calls.
  final CoinGeckoService Function(String vsCurrency)? _coinGeckoFactory;

  PriceUpdateService({
    required AssetRepository assetRepository,
    YahooFinanceService? yahooService,
    CurrencyConverterService? currencyConverter,
    GoldPriceService? goldPriceService,
    PriceCacheService? priceCache,
    CoinGeckoService Function(String vsCurrency)? coinGeckoFactory,
  })  : _assetRepository = assetRepository,
        _yahooService = yahooService ?? YahooFinanceService(),
        _currencyConverter = currencyConverter ?? CurrencyConverterService(),
        _goldPriceService = goldPriceService ?? GoldPriceService(),
        _priceCache = priceCache ?? PriceCacheService(),
        _coinGeckoFactory = coinGeckoFactory;

  CoinGeckoService _makeCoinGecko(String vsCurrency) {
    if (_coinGeckoFactory != null) return _coinGeckoFactory!(vsCurrency);
    return CoinGeckoService(vsCurrency: vsCurrency.toLowerCase());
  }

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

    // Split by type
    final cryptoAssets =
        trackable.where((a) => a.type == AssetType.crypto).toList();
    final goldAssets =
        trackable.where((a) => a.type == AssetType.gold).toList();
    final otherAssets = trackable
        .where((a) => a.type != AssetType.crypto && a.type != AssetType.gold)
        .toList();

    // --- Handle crypto (batched via CoinGecko) ---
    if (cryptoAssets.isNotEmpty) {
      final symbols = cryptoAssets
          .map((a) => _getSymbol(a))
          .where((s) => s != null)
          .cast<String>()
          .toList();

      final cryptoService = _makeCoinGecko(baseCurrency);
      final results = await cryptoService.fetchMultiplePrices(symbols);

      for (int i = 0; i < cryptoAssets.length; i++) {
        final asset = cryptoAssets[i];
        if (i >= results.length) break;
        final result = results[i];

        if (result.success) {
          await _priceCache.cachePrice(result);
          await _assetRepository.updateAssetPrice(asset.id, result.price);
          updated++;
        } else {
          // Attempt cache fallback
          final cached = _priceCache.getCachedResult(
              _getSymbol(asset) ?? asset.name);
          if (cached.success) {
            await _assetRepository.updateAssetPrice(asset.id, cached.price);
            updated++;
          } else {
            failed++;
            errors.add('${asset.name}: ${result.error}');
          }
        }
      }
    }

    // --- Handle gold (COMEX GC=F → USD/gram → INR/gram with Indian taxes) ---
    // All gold assets share the same international price, so fetch once
    // and reuse for all gold assets (with per-asset currency conversion).
    if (goldAssets.isNotEmpty) {
      final primaryCurrency = goldAssets.first.currency.isNotEmpty
          ? goldAssets.first.currency
          : baseCurrency;

      final breakdown = await _goldPriceService.fetchGoldPriceBreakdown(
        targetCurrency: primaryCurrency,
      );

      if (breakdown == null) {
        for (final asset in goldAssets) {
          // Attempt cache fallback for gold
          final cached = _priceCache.getCachedResult(PriceSymbols.goldComex);
          if (cached.success) {
            await _assetRepository.updateAssetPrice(asset.id, cached.price);
            updated++;
          } else {
            failed++;
            errors.add(
              '${asset.name}: Could not fetch COMEX gold price (GC=F). '
              'Check internet connection.',
            );
          }
        }
      } else {
        for (final asset in goldAssets) {
          final targetCurrency =
              asset.currency.isNotEmpty ? asset.currency : baseCurrency;

          double pricePerGram;
          if (targetCurrency == primaryCurrency) {
            pricePerGram = breakdown.finalPerGram;
          } else {
            double targetForexRate;
            if (exchangeRates.success) {
              targetForexRate = exchangeRates.getRate(targetCurrency);
            } else {
              targetForexRate =
                  CurrencyConverterService.fallbackRate(targetCurrency);
              errors.add(
                  'Warning: using approximate forex rate for ${asset.name}');
            }
            final basePerGramInTarget = breakdown.usdPerGram * targetForexRate;
            final taxConfig = targetCurrency == 'INR'
                ? GoldTaxConfig.india
                : GoldTaxConfig.none;
            pricePerGram = basePerGramInTarget * taxConfig.totalTaxMultiplier;
          }

          // Cache gold price under GC=F symbol
          await _priceCache.cachePrice(PriceResult(
            symbol: PriceSymbols.goldComex,
            price: pricePerGram,
            currency: targetCurrency,
            fetchedAt: DateTime.now(),
            success: true,
          ));
          await _assetRepository.updateAssetPrice(asset.id, pricePerGram);
          updated++;
        }
      }
    }

    // --- Handle stocks, bonds (Yahoo Finance) ---
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

        if (result.currency == 'USD' &&
            assetCurrency != 'USD' &&
            exchangeRates.success) {
          price = exchangeRates.convert(price, assetCurrency);
        }

        final finalResult = PriceResult(
          symbol: symbol,
          price: price,
          currency: assetCurrency,
          fetchedAt: DateTime.now(),
          success: true,
        );
        await _priceCache.cachePrice(finalResult);
        await _assetRepository.updateAssetPrice(asset.id, price);
        updated++;
      } else {
        // Attempt cache fallback
        final cached = _priceCache.getCachedResult(symbol);
        if (cached.success) {
          await _assetRepository.updateAssetPrice(asset.id, cached.price);
          updated++;
        } else {
          failed++;
          errors.add('${asset.name} ($symbol): ${result.error}');
        }
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
      final targetCurrency =
          asset.currency.isNotEmpty ? asset.currency : baseCurrency;
      final cryptoService = _makeCoinGecko(targetCurrency);
      final result = await cryptoService.fetchPrice(symbol);

      if (result.success) {
        await _priceCache.cachePrice(result);
        await _assetRepository.updateAssetPrice(asset.id, result.price);
      } else {
        final cached = _priceCache.getCachedResult(symbol);
        if (cached.success) {
          await _assetRepository.updateAssetPrice(asset.id, cached.price);
          return cached;
        }
      }
      return result;
    }

    if (asset.type == AssetType.gold) {
      final targetCurrency =
          asset.currency.isNotEmpty ? asset.currency : baseCurrency;

      final breakdown = await _goldPriceService.fetchGoldPriceBreakdown(
        targetCurrency: targetCurrency,
      );

      if (breakdown == null) {
        final cached = _priceCache.getCachedResult(PriceSymbols.goldComex);
        if (cached.success) {
          await _assetRepository.updateAssetPrice(asset.id, cached.price);
          return cached;
        }
        return PriceResult.failure(
          asset.name,
          'Could not fetch COMEX gold price (GC=F). Check internet connection.',
        );
      }

      final liveResult = PriceResult(
        symbol: PriceSymbols.goldComex,
        price: breakdown.finalPerGram,
        currency: targetCurrency,
        fetchedAt: DateTime.now(),
        success: true,
      );
      await _priceCache.cachePrice(liveResult);
      await _assetRepository.updateAssetPrice(asset.id, breakdown.finalPerGram);
      return liveResult;
    }

    // Stocks / bonds via Yahoo Finance
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

      final finalResult = PriceResult(
        symbol: symbol,
        price: price,
        currency: asset.currency.isNotEmpty ? asset.currency : baseCurrency,
        fetchedAt: DateTime.now(),
        success: true,
      );
      await _priceCache.cachePrice(finalResult);
      await _assetRepository.updateAssetPrice(asset.id, price);
      return finalResult;
    }

    // Fallback to cache
    final cached = _priceCache.getCachedResult(symbol);
    if (cached.success) {
      await _assetRepository.updateAssetPrice(asset.id, cached.price);
      return cached;
    }

    return result;
  }

  /// Determines if an asset can be auto-tracked
  bool _isTrackable(Asset asset, {String baseCurrency = 'INR'}) {
    if (!PriceSymbols.supportsAutoTracking(asset.type)) return false;
    return _getSymbol(asset, baseCurrency: baseCurrency) != null;
  }

  /// Gets the effective symbol for an asset (user-set or auto-default).
  String? _getSymbol(Asset asset, {String baseCurrency = 'INR'}) {
    final userSymbol = asset.symbol?.trim();
    if (userSymbol != null && userSymbol.isNotEmpty) return userSymbol;
    return PriceSymbols.defaultSymbol(asset.type, baseCurrency: baseCurrency);
  }
}
