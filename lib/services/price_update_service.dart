import '../core/utils/result.dart';
import '../data/models/asset.dart';
import '../data/models/asset_type.dart';
import '../data/repositories/asset_repository.dart';
import 'coingecko_service.dart';
import 'cryptocompare_service.dart';
import 'currency_converter_service.dart';
import 'gold_price_service.dart';
import 'mutual_fund_service.dart';
import 'price_cache_service.dart';
import 'price_service.dart';
import 'stooq_service.dart';
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

/// Accumulator used by per-type refresh handlers.
typedef _RefreshStats = ({int updated, int failed, List<String> errors});

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
///   On success, prices are stored in [PriceCacheService].
///   On failure, the last known cached price is used as a fallback — served
///   up to 7 days old (flagged stale past 30 min), then treated as missing.
///   Fallback prices keep their original fetch time on the asset so stale
///   data is never stamped as fresh.
class PriceUpdateService {
  final AssetRepository _assetRepository;
  final YahooFinanceService _yahooService;
  final StooqService _stooqService;
  final CurrencyConverterService _currencyConverter;
  final GoldPriceService _goldPriceService;
  final MutualFundService _mutualFundService;
  final PriceCacheService _priceCache;
  final CoinGeckoService Function(String vsCurrency)? _coinGeckoFactory;
  final CryptoCompareService Function(String vsCurrency)?
      _cryptoFallbackFactory;

  PriceUpdateService({
    required AssetRepository assetRepository,
    YahooFinanceService? yahooService,
    StooqService? stooqService,
    CurrencyConverterService? currencyConverter,
    GoldPriceService? goldPriceService,
    MutualFundService? mutualFundService,
    PriceCacheService? priceCache,
    CoinGeckoService Function(String vsCurrency)? coinGeckoFactory,
    CryptoCompareService Function(String vsCurrency)? cryptoFallbackFactory,
  })  : _assetRepository = assetRepository,
        _yahooService = yahooService ?? YahooFinanceService(),
        _stooqService = stooqService ?? StooqService(),
        _currencyConverter = currencyConverter ?? CurrencyConverterService(),
        _goldPriceService = goldPriceService ?? GoldPriceService(),
        _mutualFundService = mutualFundService ?? MutualFundService(),
        _priceCache = priceCache ?? PriceCacheService(),
        _coinGeckoFactory = coinGeckoFactory,
        _cryptoFallbackFactory = cryptoFallbackFactory;

  /// Equity-style sources tried in order (stocks, mutual funds, bonds).
  late final List<PriceService> _equitySources = [
    _yahooService,
    _stooqService,
  ];

  CoinGeckoService _makeCoinGecko(String vsCurrency) {
    if (_coinGeckoFactory != null) return _coinGeckoFactory(vsCurrency);
    return CoinGeckoService(vsCurrency: vsCurrency.toLowerCase());
  }

  CryptoCompareService _makeCryptoFallback(String vsCurrency) {
    if (_cryptoFallbackFactory != null) {
      return _cryptoFallbackFactory(vsCurrency);
    }
    return CryptoCompareService(vsCurrency: vsCurrency.toLowerCase());
  }

  /// Try each equity source in order until one returns a success.
  Future<PriceResult> _fetchEquityPrice(String symbol) async {
    PriceResult? last;
    for (final source in _equitySources) {
      last = await source.fetchPrice(symbol);
      if (last.success) return last;
    }
    return last ?? PriceResult.failure(symbol, 'No price sources configured');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Refresh prices for all assets that have a symbol or auto-trackable type.
  Future<PriceRefreshResult> refreshAllPrices() async {
    final assets = _assetRepository.getAllAssets();
    final baseCurrency = _assetRepository.getBaseCurrency();
    final trackable = assets
        .where((a) => _isTrackable(a, baseCurrency: baseCurrency))
        .toList();

    final skipped = assets.length - trackable.length;

    // Pre-fetch exchange rates once for all conversions this session
    final exchangeRates = await _currencyConverter.fetchRates();

    final cryptoStats = await _refreshCryptoAssets(
      trackable.where((a) => a.type == AssetType.crypto).toList(),
      baseCurrency,
    );
    final goldStats = await _refreshGoldAssets(
      trackable.where((a) => a.type == AssetType.gold).toList(),
      baseCurrency,
      exchangeRates,
    );
    final mfStats = await _refreshMutualFundAssets(
      trackable.where((a) => a.type == AssetType.mutualFund).toList(),
    );
    // Stocks and bonds share the equity path (Yahoo → Stooq); mutual funds
    // and the other typed buckets are handled separately above.
    final stockStats = await _refreshStockBondAssets(
      trackable
          .where((a) =>
              a.type != AssetType.crypto &&
              a.type != AssetType.gold &&
              a.type != AssetType.mutualFund)
          .toList(),
      baseCurrency,
      exchangeRates,
    );

    return PriceRefreshResult(
      total: assets.length,
      updated: cryptoStats.updated +
          goldStats.updated +
          mfStats.updated +
          stockStats.updated,
      skipped: skipped,
      failed: cryptoStats.failed +
          goldStats.failed +
          mfStats.failed +
          stockStats.failed,
      errors: <String>[
        ...cryptoStats.errors,
        ...goldStats.errors,
        ...mfStats.errors,
        ...stockStats.errors,
      ],
      completedAt: DateTime.now(),
    );
  }

  /// Refresh price for a single asset with proper currency conversion.
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
      return _refreshSingleCrypto(asset, symbol, baseCurrency);
    }
    if (asset.type == AssetType.gold) {
      return _refreshSingleGold(asset, baseCurrency);
    }
    if (asset.type == AssetType.mutualFund) {
      return _refreshSingleMutualFund(asset, symbol);
    }
    return _refreshSingleStockBond(asset, symbol, baseCurrency);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Per-type refresh handlers (bulk)
  // ─────────────────────────────────────────────────────────────────────────

  Future<_RefreshStats> _refreshCryptoAssets(
    List<Asset> assets,
    String baseCurrency,
  ) async {
    if (assets.isEmpty) return (updated: 0, failed: 0, errors: <String>[]);

    final symbols =
        assets.map(_getSymbol).where((s) => s != null).cast<String>().toList();

    final cryptoService = _makeCoinGecko(baseCurrency);
    final results = await cryptoService.fetchMultiplePrices(symbols);

    // Secondary provider: retry only the symbols CoinGecko failed, in one
    // batched CryptoCompare call, before touching the cache.
    final failedSymbols = <String>[
      for (int i = 0; i < results.length; i++)
        if (!results[i].success && i < symbols.length) symbols[i],
    ];
    if (failedSymbols.isNotEmpty) {
      final fallbackService = _makeCryptoFallback(baseCurrency);
      final fallbackResults =
          await fallbackService.fetchMultiplePrices(failedSymbols);
      final bySymbol = {
        for (final r in fallbackResults)
          if (r.success) r.symbol: r,
      };
      for (int i = 0; i < results.length; i++) {
        if (!results[i].success && i < symbols.length) {
          final recovered = bySymbol[symbols[i]];
          if (recovered != null) results[i] = recovered;
        }
      }
    }

    int updated = 0;
    int failed = 0;
    final errors = <String>[];

    for (int i = 0; i < assets.length; i++) {
      final asset = assets[i];
      if (i >= results.length) break;
      final result = results[i];

      if (result.success) {
        await _priceCache.cachePrice(result);
        await _assetRepository.updateAssetPrice(asset.id, result.price);
        updated++;
      } else {
        final cached =
            _priceCache.getCachedResult(_getSymbol(asset) ?? asset.name);
        if (cached.success) {
          await _assetRepository.updateAssetPrice(asset.id, cached.price,
              asOf: cached.fetchedAt);
          updated++;
        } else {
          failed++;
          errors.add('${asset.name}: ${result.error}');
        }
      }
    }

    return (updated: updated, failed: failed, errors: errors);
  }

  Future<_RefreshStats> _refreshGoldAssets(
    List<Asset> assets,
    String baseCurrency,
    ExchangeRateResult exchangeRates,
  ) async {
    if (assets.isEmpty) return (updated: 0, failed: 0, errors: <String>[]);

    final primaryCurrency =
        assets.first.currency.isNotEmpty ? assets.first.currency : baseCurrency;

    final breakdown = await _goldPriceService.fetchGoldPriceBreakdown(
      targetCurrency: primaryCurrency,
    );

    int updated = 0;
    int failed = 0;
    final errors = <String>[];

    if (breakdown == null) {
      for (final asset in assets) {
        final cached = _priceCache.getCachedResult(PriceSymbols.goldComex);
        if (cached.success) {
          await _assetRepository.updateAssetPrice(asset.id, cached.price,
              asOf: cached.fetchedAt);
          updated++;
        } else {
          failed++;
          errors.add(
            '${asset.name}: Could not fetch COMEX gold price (GC=F). '
            'Check internet connection.',
          );
        }
      }
      return (updated: updated, failed: failed, errors: errors);
    }

    for (final asset in assets) {
      final targetCurrency =
          asset.currency.isNotEmpty ? asset.currency : baseCurrency;

      double pricePerGram;
      if (targetCurrency == primaryCurrency) {
        pricePerGram = breakdown.finalPerGram;
      } else {
        final targetRate = exchangeRates.success
            ? exchangeRates.getRate(targetCurrency)
            : CurrencyConverterService.fallbackRate(targetCurrency);
        if (!exchangeRates.success) {
          errors.add('Warning: using approximate forex rate for ${asset.name}');
        }
        final basePerGramInTarget = breakdown.usdPerGram * targetRate;
        final taxConfig =
            targetCurrency == 'INR' ? GoldTaxConfig.india : GoldTaxConfig.none;
        pricePerGram = basePerGramInTarget * taxConfig.totalTaxMultiplier;
      }

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

    return (updated: updated, failed: failed, errors: errors);
  }

  Future<_RefreshStats> _refreshMutualFundAssets(List<Asset> assets) async {
    if (assets.isEmpty) return (updated: 0, failed: 0, errors: <String>[]);

    int updated = 0;
    int failed = 0;
    final errors = <String>[];

    for (final asset in assets) {
      final symbol = _getSymbol(asset);
      if (symbol == null) continue;

      final result = await _fetchMutualFundNav(symbol);
      if (result.success) {
        await _priceCache.cachePrice(result);
        await _assetRepository.updateAssetPrice(asset.id, result.price);
        updated++;
      } else {
        final cached = _priceCache.getCachedResult(symbol);
        if (cached.success) {
          await _assetRepository.updateAssetPrice(asset.id, cached.price,
              asOf: cached.fetchedAt);
          updated++;
        } else {
          failed++;
          errors.add('${asset.name} ($symbol): ${result.error}');
        }
      }

      // Throttle to be gentle on MFAPI.in
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    return (updated: updated, failed: failed, errors: errors);
  }

  Future<_RefreshStats> _refreshStockBondAssets(
    List<Asset> assets,
    String baseCurrency,
    ExchangeRateResult exchangeRates,
  ) async {
    int updated = 0;
    int failed = 0;
    final errors = <String>[];

    for (final asset in assets) {
      final symbol = _getSymbol(asset);
      if (symbol == null) {
        // No symbol → skip silently (already counted in outer skipped tally)
        continue;
      }

      final result = await _fetchEquityPrice(symbol);

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
        final cached = _priceCache.getCachedResult(symbol);
        if (cached.success) {
          await _assetRepository.updateAssetPrice(asset.id, cached.price,
              asOf: cached.fetchedAt);
          updated++;
        } else {
          failed++;
          errors.add('${asset.name} ($symbol): ${result.error}');
        }
      }

      // Throttle calls to avoid rate limiting
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    return (updated: updated, failed: failed, errors: errors);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Per-type refresh handlers (single)
  // ─────────────────────────────────────────────────────────────────────────

  Future<PriceResult> _refreshSingleCrypto(
      Asset asset, String symbol, String baseCurrency) async {
    final targetCurrency =
        asset.currency.isNotEmpty ? asset.currency : baseCurrency;
    final cryptoService = _makeCoinGecko(targetCurrency);
    var result = await cryptoService.fetchPrice(symbol);

    // Secondary provider before falling back to the cache
    if (!result.success) {
      final fallbackResult =
          await _makeCryptoFallback(targetCurrency).fetchPrice(symbol);
      if (fallbackResult.success) result = fallbackResult;
    }

    if (result.success) {
      await _priceCache.cachePrice(result);
      await _assetRepository.updateAssetPrice(asset.id, result.price);
      return result;
    }

    final cached = _priceCache.getCachedResult(symbol);
    if (cached.success) {
      await _assetRepository.updateAssetPrice(asset.id, cached.price,
          asOf: cached.fetchedAt);
    }
    return cached.success ? cached : result;
  }

  Future<PriceResult> _refreshSingleGold(
      Asset asset, String baseCurrency) async {
    final targetCurrency =
        asset.currency.isNotEmpty ? asset.currency : baseCurrency;

    final breakdown = await _goldPriceService.fetchGoldPriceBreakdown(
      targetCurrency: targetCurrency,
    );

    if (breakdown == null) {
      final cached = _priceCache.getCachedResult(PriceSymbols.goldComex);
      if (cached.success) {
        await _assetRepository.updateAssetPrice(asset.id, cached.price,
            asOf: cached.fetchedAt);
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

  Future<PriceResult> _refreshSingleMutualFund(
      Asset asset, String symbol) async {
    final result = await _fetchMutualFundNav(symbol);
    if (result.success) {
      await _priceCache.cachePrice(result);
      await _assetRepository.updateAssetPrice(asset.id, result.price);
      return result;
    }

    final cached = _priceCache.getCachedResult(symbol);
    if (cached.success) {
      await _assetRepository.updateAssetPrice(asset.id, cached.price,
          asOf: cached.fetchedAt);
      return cached;
    }
    return result;
  }

  /// Fetch a mutual fund's latest NAV (INR) from MFAPI.in.
  ///
  /// The stored symbol is the numeric AMFI scheme code. If it is not numeric
  /// (e.g. a user entered an ETF-proxy ticker like NIFTYBEES.NS), fall back to
  /// the equity path so those still resolve.
  Future<PriceResult> _fetchMutualFundNav(String symbol) async {
    final schemeCode = int.tryParse(symbol);
    if (schemeCode == null) {
      return _fetchEquityPrice(symbol);
    }

    final navResult = await _mutualFundService.fetchNav(schemeCode);
    return switch (navResult) {
      Ok(:final value) when (value.nav ?? 0) > 0 => PriceResult(
          symbol: symbol,
          price: value.nav!,
          currency: 'INR', // MFAPI.in quotes NAV in INR
          fetchedAt: DateTime.now(),
          success: true,
        ),
      Ok() => PriceResult.failure(symbol, 'No NAV available for scheme $symbol'),
      Err(:final message) => PriceResult.failure(symbol, message),
    };
  }

  Future<PriceResult> _refreshSingleStockBond(
      Asset asset, String symbol, String baseCurrency) async {
    final result = await _fetchEquityPrice(symbol);

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

    final cached = _priceCache.getCachedResult(symbol);
    if (cached.success) {
      await _assetRepository.updateAssetPrice(asset.id, cached.price,
          asOf: cached.fetchedAt);
      return cached;
    }
    return result;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  bool _isTrackable(Asset asset, {String baseCurrency = 'INR'}) {
    if (!PriceSymbols.supportsAutoTracking(asset.type)) return false;
    return _getSymbol(asset, baseCurrency: baseCurrency) != null;
  }

  String? _getSymbol(Asset asset, {String baseCurrency = 'INR'}) {
    final userSymbol = asset.symbol?.trim();
    if (userSymbol != null && userSymbol.isNotEmpty) return userSymbol;
    return PriceSymbols.defaultSymbol(asset.type, baseCurrency: baseCurrency);
  }
}
