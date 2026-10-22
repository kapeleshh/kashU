import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kashu/core/utils/result.dart';
import 'package:kashu/data/models/asset.dart';
import 'package:kashu/data/models/asset_type.dart';
import 'package:kashu/data/repositories/asset_repository.dart';
import 'package:kashu/services/coingecko_service.dart';
import 'package:kashu/services/cryptocompare_service.dart';
import 'package:kashu/services/currency_converter_service.dart';
import 'package:kashu/services/gold_price_service.dart';
import 'package:kashu/services/mutual_fund_service.dart';
import 'package:kashu/services/price_cache_service.dart';
import 'package:kashu/services/price_service.dart';
import 'package:kashu/services/price_update_service.dart';
import 'package:kashu/services/stooq_service.dart';
import 'package:kashu/services/yahoo_finance_service.dart';

// ── Mocks ────────────────────────────────────────────────────────────────────

class MockAssetRepository extends Mock implements AssetRepository {}

class MockYahooFinanceService extends Mock implements YahooFinanceService {}

class MockStooqService extends Mock implements StooqService {}

class MockCurrencyConverterService extends Mock
    implements CurrencyConverterService {}

class MockGoldPriceService extends Mock implements GoldPriceService {}

class MockCoinGeckoService extends Mock implements CoinGeckoService {}

class MockCryptoCompareService extends Mock implements CryptoCompareService {}

class MockPriceCacheService extends Mock implements PriceCacheService {}

class MockMutualFundService extends Mock implements MutualFundService {}

MutualFundResult _mf(int code, double nav) => MutualFundResult(
      schemeCode: code,
      schemeName: 'Scheme $code',
      fundHouse: '',
      schemeCategory: '',
      schemeType: '',
      nav: nav,
      navDate: '01-01-2024',
    );

// ── Helpers ──────────────────────────────────────────────────────────────────

Asset _makeAsset({
  String id = 'a1',
  String name = 'Test Asset',
  String? symbol,
  AssetType type = AssetType.stock,
  String currency = 'INR',
}) {
  final now = DateTime(2024, 1, 1);
  return Asset(
    id: id,
    name: name,
    symbol: symbol,
    type: type,
    quantity: 10,
    purchasePrice: 100,
    currentPrice: 110,
    currency: currency,
    purchaseDate: now,
    createdAt: now,
    updatedAt: now,
  );
}

PriceResult _success(String symbol, double price,
    {String currency = 'INR'}) {
  return PriceResult(
    symbol: symbol,
    price: price,
    currency: currency,
    fetchedAt: DateTime.now(),
    success: true,
  );
}

/// A metal breakdown as GoldPriceService would return it: the COMEX leg in
/// USD, converted at [forexRate], with the duty set the caller asked for.
GoldPriceBreakdown _breakdown({
  double usdPerTroyOz = 2400.0,
  String currency = 'INR',
  double forexRate = 83.5,
  double importDutyRate = 0.05,
  double aidcRate = 0.01,
  double gstRate = 0.03,
}) {
  final usdPerGram = usdPerTroyOz / 31.1035;
  return GoldPriceBreakdown(
    usdPerTroyOz: usdPerTroyOz,
    usdPerGram: usdPerGram,
    forexRate: forexRate,
    basePerGram: usdPerGram * forexRate,
    importDutyRate: importDutyRate,
    aidcRate: aidcRate,
    gstRate: gstRate,
    targetCurrency: currency,
    usedLiveForex: true,
  );
}

ExchangeRateResult _fxSuccess({double inr = 83.5}) {
  return ExchangeRateResult(
    base: 'USD',
    rates: {'INR': inr, 'USD': 1.0},
    fetchedAt: DateTime.now(),
    success: true,
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    // Mocktail requires fallback values for any custom type used with any()
    registerFallbackValue(PriceResult(
      symbol: '',
      price: 0,
      currency: '',
      fetchedAt: DateTime(2024),
      success: false,
    ));
    registerFallbackValue(<String>[]);
    registerFallbackValue(DateTime(2024));
  });

  late MockAssetRepository mockRepo;
  late MockYahooFinanceService mockYahoo;
  late MockStooqService mockStooq;
  late MockCurrencyConverterService mockFx;
  late MockGoldPriceService mockGold;
  late MockPriceCacheService mockCache;
  late MockCoinGeckoService mockCoinGecko;
  late MockCryptoCompareService mockCryptoCompare;
  late MockMutualFundService mockMutualFund;
  late PriceUpdateService service;

  setUp(() {
    mockRepo = MockAssetRepository();
    mockYahoo = MockYahooFinanceService();
    mockStooq = MockStooqService();
    mockFx = MockCurrencyConverterService();
    mockGold = MockGoldPriceService();
    mockCache = MockPriceCacheService();
    mockCoinGecko = MockCoinGeckoService();
    mockCryptoCompare = MockCryptoCompareService();
    mockMutualFund = MockMutualFundService();

    // Default: cache returns miss (no cached price)
    when(() => mockCache.cachePrice(any())).thenAnswer((_) async {});
    when(() => mockCache.getCachedResult(any(), any()))
        .thenReturn(PriceResult.failure('x', 'no cache'));

    // Default: fallback providers fail too (individual tests override).
    // Injecting them keeps the tests hermetic — no real network attempts.
    when(() => mockStooq.fetchPrice(any())).thenAnswer((inv) async =>
        PriceResult.failure(
            inv.positionalArguments.first as String, 'stooq unavailable'));
    when(() => mockCryptoCompare.fetchPrice(any())).thenAnswer((inv) async =>
        PriceResult.failure(inv.positionalArguments.first as String,
            'cryptocompare unavailable'));
    when(() => mockCryptoCompare.fetchMultiplePrices(any())).thenAnswer(
        (inv) async => (inv.positionalArguments.first as List<String>)
            .map((s) => PriceResult.failure(s, 'cryptocompare unavailable'))
            .toList());

    // Default: NAV fetch fails (individual tests override). Keeps tests
    // hermetic — no real MFAPI.in call.
    when(() => mockMutualFund.fetchNav(any())).thenAnswer(
        (inv) async => Err('mfapi unavailable'));

    service = PriceUpdateService(
      assetRepository: mockRepo,
      yahooService: mockYahoo,
      stooqService: mockStooq,
      currencyConverter: mockFx,
      goldPriceService: mockGold,
      mutualFundService: mockMutualFund,
      priceCache: mockCache,
      coinGeckoFactory: (_) => mockCoinGecko,
      cryptoFallbackFactory: (_) => mockCryptoCompare,
    );
  });

  group('refreshAllPrices — empty portfolio', () {
    test('returns zero counts when no assets', () async {
      when(() => mockRepo.getAllAssets()).thenReturn([]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer((_) async => _fxSuccess());

      final result = await service.refreshAllPrices();

      expect(result.total, 0);
      expect(result.updated, 0);
      expect(result.failed, 0);
    });
  });

  group('refreshAllPrices — stocks via Yahoo Finance', () {
    test('updates price for a stock with a symbol', () async {
      final asset = _makeAsset(
          id: 's1', symbol: 'RELIANCE.NS', type: AssetType.stock);
      when(() => mockRepo.getAllAssets()).thenReturn([asset]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer((_) async => _fxSuccess());
      when(() => mockYahoo.fetchPrice('RELIANCE.NS'))
          .thenAnswer((_) async => _success('RELIANCE.NS', 2850.0));
      when(() => mockRepo.updateAssetPrice('s1', any()))
          .thenAnswer((_) async {});

      final result = await service.refreshAllPrices();

      expect(result.updated, 1);
      expect(result.failed, 0);
      verify(() => mockRepo.updateAssetPrice('s1', any())).called(1);
    });

    test('counts as failed when Yahoo returns error and no cache', () async {
      final asset = _makeAsset(
          id: 's1', symbol: 'INVALID.NS', type: AssetType.stock);
      when(() => mockRepo.getAllAssets()).thenReturn([asset]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer((_) async => _fxSuccess());
      when(() => mockYahoo.fetchPrice('INVALID.NS'))
          .thenAnswer((_) async =>
              PriceResult.failure('INVALID.NS', 'not found'));

      final result = await service.refreshAllPrices();

      expect(result.failed, 1);
      expect(result.errors, isNotEmpty);
    });

    test('uses cache fallback when Yahoo fails', () async {
      final asset = _makeAsset(
          id: 's1', symbol: 'RELIANCE.NS', type: AssetType.stock);
      when(() => mockRepo.getAllAssets()).thenReturn([asset]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer((_) async => _fxSuccess());
      when(() => mockYahoo.fetchPrice('RELIANCE.NS'))
          .thenAnswer((_) async =>
              PriceResult.failure('RELIANCE.NS', 'timeout'));
      // Cache has a valid price
      final cachedAt = DateTime.now().subtract(const Duration(hours: 2));
      when(() => mockCache.getCachedResult('RELIANCE.NS', 'INR')).thenReturn(
          PriceResult(
              symbol: 'RELIANCE.NS',
              price: 2800.0,
              currency: 'INR',
              fetchedAt: cachedAt,
              success: true,
              isStale: true));
      when(() => mockRepo.updateAssetPrice('s1', 2800.0,
          asOf: any(named: 'asOf'))).thenAnswer((_) async {});

      final result = await service.refreshAllPrices();

      expect(result.updated, 1);
      expect(result.failed, 0);
      // The fallback must carry the cached fetch time, not "now" — stale
      // data must not be stamped fresh.
      verify(() => mockRepo.updateAssetPrice('s1', 2800.0, asOf: cachedAt))
          .called(1);
    });

    test('falls back to Stooq when Yahoo fails', () async {
      final asset = _makeAsset(
          id: 's1', symbol: 'RELIANCE.NS', type: AssetType.stock);
      when(() => mockRepo.getAllAssets()).thenReturn([asset]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer((_) async => _fxSuccess());
      when(() => mockYahoo.fetchPrice('RELIANCE.NS'))
          .thenAnswer((_) async =>
              PriceResult.failure('RELIANCE.NS', 'timeout'));
      when(() => mockStooq.fetchPrice('RELIANCE.NS'))
          .thenAnswer((_) async => _success('RELIANCE.NS', 2810.0));
      when(() => mockRepo.updateAssetPrice('s1', 2810.0))
          .thenAnswer((_) async {});

      final result = await service.refreshAllPrices();

      expect(result.updated, 1);
      expect(result.failed, 0);
      verify(() => mockRepo.updateAssetPrice('s1', 2810.0)).called(1);
      verifyNever(() => mockCache.getCachedResult(any(), any()));
    });

    test('skips non-trackable asset types (e.g. cash)', () async {
      final cashAsset = _makeAsset(
          id: 'c1', type: AssetType.cash, symbol: null);
      when(() => mockRepo.getAllAssets()).thenReturn([cashAsset]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer((_) async => _fxSuccess());

      final result = await service.refreshAllPrices();

      expect(result.skipped, 1);
      expect(result.updated, 0);
      verifyNever(() => mockYahoo.fetchPrice(any()));
    });

    test('converts USD price to INR using exchange rates', () async {
      final asset = _makeAsset(
          id: 's1', symbol: 'AAPL', type: AssetType.stock, currency: 'INR');
      when(() => mockRepo.getAllAssets()).thenReturn([asset]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates())
          .thenAnswer((_) async => _fxSuccess(inr: 83.5));
      when(() => mockYahoo.fetchPrice('AAPL'))
          .thenAnswer((_) async => _success('AAPL', 200.0, currency: 'USD'));

      double? storedPrice;
      when(() => mockRepo.updateAssetPrice('s1', any()))
          .thenAnswer((inv) async {
        storedPrice = inv.positionalArguments[1] as double;
      });

      await service.refreshAllPrices();

      // 200 USD * 83.5 = 16700 INR
      expect(storedPrice, closeTo(16700.0, 1.0));
    });
  });

  group('refreshAllPrices — crypto via CoinGecko', () {
    test('updates price for a crypto asset', () async {
      final asset = _makeAsset(
          id: 'cr1',
          symbol: 'bitcoin',
          type: AssetType.crypto,
          currency: 'INR');
      when(() => mockRepo.getAllAssets()).thenReturn([asset]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer((_) async => _fxSuccess());
      when(() => mockCoinGecko.fetchMultiplePrices(any()))
          .thenAnswer((_) async => [_success('bitcoin', 5800000.0)]);
      when(() => mockRepo.updateAssetPrice('cr1', any()))
          .thenAnswer((_) async {});

      final result = await service.refreshAllPrices();

      expect(result.updated, 1);
      expect(result.failed, 0);
    });

    test('uses cache fallback when CoinGecko fails', () async {
      final asset = _makeAsset(
          id: 'cr1', symbol: 'bitcoin', type: AssetType.crypto);
      when(() => mockRepo.getAllAssets()).thenReturn([asset]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer((_) async => _fxSuccess());
      when(() => mockCoinGecko.fetchMultiplePrices(any()))
          .thenAnswer((_) async => [
                PriceResult.failure('bitcoin', 'rate limit'),
              ]);
      when(() => mockCache.getCachedResult('bitcoin', 'INR'))
          .thenReturn(_success('bitcoin', 5750000.0));
      when(() => mockRepo.updateAssetPrice('cr1', 5750000.0,
          asOf: any(named: 'asOf'))).thenAnswer((_) async {});

      final result = await service.refreshAllPrices();

      expect(result.updated, 1);
      verify(() => mockRepo.updateAssetPrice('cr1', 5750000.0,
          asOf: any(named: 'asOf'))).called(1);
    });

    test('uses CryptoCompare fallback before the cache when CoinGecko fails',
        () async {
      final asset = _makeAsset(
          id: 'cr1', symbol: 'bitcoin', type: AssetType.crypto);
      when(() => mockRepo.getAllAssets()).thenReturn([asset]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer((_) async => _fxSuccess());
      when(() => mockCoinGecko.fetchMultiplePrices(any()))
          .thenAnswer((_) async => [
                PriceResult.failure('bitcoin', 'rate limit'),
              ]);
      when(() => mockCryptoCompare.fetchMultiplePrices(['bitcoin']))
          .thenAnswer((_) async => [_success('bitcoin', 5820000.0)]);
      when(() => mockRepo.updateAssetPrice('cr1', 5820000.0))
          .thenAnswer((_) async {});

      final result = await service.refreshAllPrices();

      expect(result.updated, 1);
      expect(result.failed, 0);
      // The recovered price is stored AND written to the cache; the stale
      // cache fallback is never consulted.
      verify(() => mockRepo.updateAssetPrice('cr1', 5820000.0)).called(1);
      verify(() => mockCache.cachePrice(any(
          that: predicate<PriceResult>(
              (r) => r.symbol == 'bitcoin' && r.price == 5820000.0))))
          .called(1);
      verifyNever(() => mockCache.getCachedResult(any(), any()));
    });

    test('single-asset refresh falls back to CryptoCompare', () async {
      final asset = _makeAsset(
          id: 'cr1', symbol: 'ethereum', type: AssetType.crypto);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockCoinGecko.fetchPrice('ethereum')).thenAnswer(
          (_) async => PriceResult.failure('ethereum', 'rate limit'));
      when(() => mockCryptoCompare.fetchPrice('ethereum'))
          .thenAnswer((_) async => _success('ethereum', 310000.0));
      when(() => mockRepo.updateAssetPrice('cr1', 310000.0))
          .thenAnswer((_) async {});

      final result = await service.refreshSinglePrice(asset);

      expect(result.success, true);
      expect(result.price, 310000.0);
      verify(() => mockRepo.updateAssetPrice('cr1', 310000.0)).called(1);
    });
  });

  group('refreshAllPrices — metals via GoldPriceService', () {
    /// Stub the metal fetch, returning whatever [answer] maps the requested
    /// COMEX symbol to.
    void stubMetal(GoldPriceBreakdown? Function(String comexSymbol) answer) {
      when(() => mockGold.fetchMetalPriceBreakdown(
            comexSymbol: any(named: 'comexSymbol'),
            targetCurrency: any(named: 'targetCurrency'),
            taxConfig: any(named: 'taxConfig'),
          )).thenAnswer(
          (inv) async => answer(inv.namedArguments[#comexSymbol] as String));
    }

    test('updates gold price with final INR/gram', () async {
      final asset = _makeAsset(
          id: 'g1', type: AssetType.gold, currency: 'INR');
      when(() => mockRepo.getAllAssets()).thenReturn([asset]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer((_) async => _fxSuccess());

      final breakdown = _breakdown();
      stubMetal((_) => breakdown);
      when(() => mockRepo.updateAssetPrice('g1', any()))
          .thenAnswer((_) async {});

      final result = await service.refreshAllPrices();

      expect(result.updated, 1);
      verify(() => mockRepo.updateAssetPrice('g1', breakdown.finalPerGram))
          .called(1);
    });

    test('uses cache fallback when the metal API fails', () async {
      final asset = _makeAsset(
          id: 'g1', type: AssetType.gold, currency: 'INR');
      when(() => mockRepo.getAllAssets()).thenReturn([asset]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer((_) async => _fxSuccess());
      stubMetal((_) => null);
      when(() => mockCache.getCachedResult(PriceSymbols.goldComex, 'INR'))
          .thenReturn(_success(PriceSymbols.goldComex, 6500.0));
      when(() => mockRepo.updateAssetPrice('g1', 6500.0,
          asOf: any(named: 'asOf'))).thenAnswer((_) async {});

      final result = await service.refreshAllPrices();

      expect(result.updated, 1);
      verify(() => mockRepo.updateAssetPrice('g1', 6500.0,
          asOf: any(named: 'asOf'))).called(1);
    });

    test('silver is priced against SI=F with the silver duty set', () async {
      // Silver is stored as an AssetType.gold asset carrying SI=F. Pricing it
      // against GC=F would overstate a holding by roughly 100x.
      final asset = _makeAsset(
          id: 's1',
          symbol: PriceSymbols.silverComex,
          type: AssetType.gold,
          currency: 'INR');
      when(() => mockRepo.getAllAssets()).thenReturn([asset]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer((_) async => _fxSuccess());
      stubMetal((_) => _breakdown(
            usdPerTroyOz: 30.0,
            importDutyRate: 0.10,
            aidcRate: 0.0,
          ));
      when(() => mockRepo.updateAssetPrice('s1', any()))
          .thenAnswer((_) async {});

      final result = await service.refreshAllPrices();
      expect(result.updated, 1);

      final captured = verify(() => mockGold.fetchMetalPriceBreakdown(
            comexSymbol: captureAny(named: 'comexSymbol'),
            targetCurrency: any(named: 'targetCurrency'),
            taxConfig: captureAny(named: 'taxConfig'),
          )).captured;

      expect(captured[0], PriceSymbols.silverComex);
      final tax = captured[1] as GoldTaxConfig;
      expect(tax.importDutyRate, 0.10); // silver BCD, not gold's 5%
      expect(tax.aidcRate, 0.0); // silver pays no AIDC
    });

    test('gold and silver held together each hit their own contract',
        () async {
      final gold = _makeAsset(
          id: 'g1', type: AssetType.gold, currency: 'INR');
      final silver = _makeAsset(
          id: 's1',
          symbol: PriceSymbols.silverComex,
          type: AssetType.gold,
          currency: 'INR');
      when(() => mockRepo.getAllAssets()).thenReturn([gold, silver]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer((_) async => _fxSuccess());

      final goldBreakdown = _breakdown(usdPerTroyOz: 2400.0);
      final silverBreakdown = _breakdown(
          usdPerTroyOz: 30.0, importDutyRate: 0.10, aidcRate: 0.0);
      stubMetal((symbol) => PriceSymbols.isComexSilver(symbol)
          ? silverBreakdown
          : goldBreakdown);
      when(() => mockRepo.updateAssetPrice(any(), any()))
          .thenAnswer((_) async {});

      final result = await service.refreshAllPrices();

      expect(result.updated, 2);
      verify(() => mockRepo.updateAssetPrice('g1', goldBreakdown.finalPerGram))
          .called(1);
      verify(() =>
              mockRepo.updateAssetPrice('s1', silverBreakdown.finalPerGram))
          .called(1);
    });

    test('a second currency is re-derived from USD, not given the INR price',
        () async {
      final inrGold = _makeAsset(
          id: 'g1', type: AssetType.gold, currency: 'INR');
      final usdGold = _makeAsset(
          id: 'g2', type: AssetType.gold, currency: 'USD');
      when(() => mockRepo.getAllAssets()).thenReturn([inrGold, usdGold]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer((_) async => _fxSuccess());

      final breakdown = _breakdown();
      stubMetal((_) => breakdown);
      when(() => mockRepo.updateAssetPrice(any(), any()))
          .thenAnswer((_) async {});

      final result = await service.refreshAllPrices();

      expect(result.updated, 2);
      verify(() => mockRepo.updateAssetPrice('g1', breakdown.finalPerGram))
          .called(1);
      // USD/gram, untaxed — Indian duties are an INR-only concept.
      verify(() => mockRepo.updateAssetPrice(
              'g2', any(that: closeTo(breakdown.usdPerGram, 0.0001))))
          .called(1);

      // Each currency caches under its own key, so neither can clobber the
      // other's per-gram number.
      final cached = verify(() => mockCache.cachePrice(captureAny())).captured
          .cast<PriceResult>();
      expect(cached.map((r) => PriceCacheService.keyFor(r.symbol, r.currency)),
          containsAll(<String>['GC=F:INR', 'GC=F:USD']));
    });

    test('offline fallback will not hand a USD holding an INR cached price',
        () async {
      final usdGold = _makeAsset(
          id: 'g2', type: AssetType.gold, currency: 'USD');
      when(() => mockRepo.getAllAssets()).thenReturn([usdGold]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer((_) async => _fxSuccess());
      stubMetal((_) => null);

      // An INR price is cached but nothing in USD is.
      when(() => mockCache.getCachedResult(PriceSymbols.goldComex, 'INR'))
          .thenReturn(_success(PriceSymbols.goldComex, 6500.0));

      final result = await service.refreshAllPrices();

      expect(result.updated, 0);
      expect(result.failed, 1);
      verifyNever(() => mockRepo.updateAssetPrice('g2', any(),
          asOf: any(named: 'asOf')));
    });
  });

  group('refreshSinglePrice', () {
    test('returns failure when asset has no symbol and no default', () async {
      final asset = _makeAsset(
          id: 's1', type: AssetType.stock, symbol: null);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');

      final result = await service.refreshSinglePrice(asset);

      expect(result.success, false);
      expect(result.error, contains('No symbol'));
    });

    test('refreshes stock price and stores it', () async {
      final asset = _makeAsset(
          id: 's1', symbol: 'TCS.NS', type: AssetType.stock, currency: 'INR');
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockYahoo.fetchPrice('TCS.NS'))
          .thenAnswer((_) async => _success('TCS.NS', 4000.0, currency: 'INR'));
      when(() => mockRepo.updateAssetPrice('s1', any()))
          .thenAnswer((_) async {});

      final result = await service.refreshSinglePrice(asset);

      expect(result.success, true);
      expect(result.price, 4000.0);
      verify(() => mockRepo.updateAssetPrice('s1', 4000.0)).called(1);
    });

    test('refreshes crypto price', () async {
      final asset = _makeAsset(
          id: 'cr1',
          symbol: 'ethereum',
          type: AssetType.crypto,
          currency: 'INR');
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockCoinGecko.fetchPrice('ethereum'))
          .thenAnswer((_) async => _success('ethereum', 300000.0));
      when(() => mockRepo.updateAssetPrice('cr1', any()))
          .thenAnswer((_) async {});

      final result = await service.refreshSinglePrice(asset);

      expect(result.success, true);
      expect(result.price, 300000.0);
    });

    test('a single silver holding refreshes against SI=F', () async {
      final asset = _makeAsset(
          id: 's1',
          symbol: PriceSymbols.silverComex,
          type: AssetType.gold,
          currency: 'INR');
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      final breakdown = _breakdown(
          usdPerTroyOz: 30.0, importDutyRate: 0.10, aidcRate: 0.0);
      when(() => mockGold.fetchMetalPriceBreakdown(
            comexSymbol: any(named: 'comexSymbol'),
            targetCurrency: any(named: 'targetCurrency'),
            taxConfig: any(named: 'taxConfig'),
          )).thenAnswer((_) async => breakdown);
      when(() => mockRepo.updateAssetPrice('s1', any()))
          .thenAnswer((_) async {});

      final result = await service.refreshSinglePrice(asset);

      expect(result.success, true);
      expect(result.symbol, PriceSymbols.silverComex);
      expect(result.price, breakdown.finalPerGram);
      verify(() => mockGold.fetchMetalPriceBreakdown(
            comexSymbol: PriceSymbols.silverComex,
            targetCurrency: 'INR',
            taxConfig: any(named: 'taxConfig'),
          )).called(1);
    });

    test('returns cached result when stock refresh fails', () async {
      final asset = _makeAsset(
          id: 's1', symbol: 'FAIL.NS', type: AssetType.stock, currency: 'INR');
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockYahoo.fetchPrice('FAIL.NS'))
          .thenAnswer((_) async =>
              PriceResult.failure('FAIL.NS', 'not found'));
      when(() => mockCache.getCachedResult('FAIL.NS', 'INR'))
          .thenReturn(_success('FAIL.NS', 3900.0));
      when(() => mockRepo.updateAssetPrice('s1', 3900.0,
          asOf: any(named: 'asOf'))).thenAnswer((_) async {});

      final result = await service.refreshSinglePrice(asset);

      expect(result.success, true);
      expect(result.price, 3900.0);
    });
  });

  group('mutual funds via MutualFundService (regression for MF refresh)', () {
    test('routes to MFAPI NAV, not the Yahoo/Stooq equity path', () async {
      final asset = _makeAsset(
          id: 'mf1', symbol: '120503', type: AssetType.mutualFund);
      when(() => mockRepo.getAllAssets()).thenReturn([asset]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer((_) async => _fxSuccess());
      when(() => mockMutualFund.fetchNav(120503))
          .thenAnswer((_) async => Ok(_mf(120503, 96.1234)));
      when(() => mockRepo.updateAssetPrice('mf1', 96.1234))
          .thenAnswer((_) async {});

      final result = await service.refreshAllPrices();

      expect(result.updated, 1);
      expect(result.failed, 0);
      verify(() => mockMutualFund.fetchNav(120503)).called(1);
      verify(() => mockRepo.updateAssetPrice('mf1', 96.1234)).called(1);
      // The old bug: MFs fell through to the equity path with a numeric
      // scheme code that never resolves. That must not happen anymore.
      verifyNever(() => mockYahoo.fetchPrice(any()));
      verifyNever(() => mockStooq.fetchPrice(any()));
    });

    test('single MF refresh returns the NAV', () async {
      final asset = _makeAsset(
          id: 'mf1', symbol: '118989', type: AssetType.mutualFund);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockMutualFund.fetchNav(118989))
          .thenAnswer((_) async => Ok(_mf(118989, 250.5)));
      when(() => mockRepo.updateAssetPrice('mf1', 250.5))
          .thenAnswer((_) async {});

      final result = await service.refreshSinglePrice(asset);

      expect(result.success, true);
      expect(result.price, 250.5);
      expect(result.currency, 'INR');
    });

    test('falls back to cache when NAV fetch fails', () async {
      final asset = _makeAsset(
          id: 'mf1', symbol: '120503', type: AssetType.mutualFund);
      when(() => mockRepo.getAllAssets()).thenReturn([asset]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer((_) async => _fxSuccess());
      when(() => mockMutualFund.fetchNav(120503))
          .thenAnswer((_) async => Err('mfapi down'));
      when(() => mockCache.getCachedResult('120503', 'INR'))
          .thenReturn(_success('120503', 94.0));
      when(() => mockRepo.updateAssetPrice('mf1', 94.0,
          asOf: any(named: 'asOf'))).thenAnswer((_) async {});

      final result = await service.refreshAllPrices();

      expect(result.updated, 1);
      verify(() => mockRepo.updateAssetPrice('mf1', 94.0,
          asOf: any(named: 'asOf'))).called(1);
    });

    test('a non-numeric symbol (ETF proxy) uses the equity path', () async {
      final asset = _makeAsset(
          id: 'mf1', symbol: 'NIFTYBEES.NS', type: AssetType.mutualFund);
      when(() => mockRepo.getAllAssets()).thenReturn([asset]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer((_) async => _fxSuccess());
      when(() => mockYahoo.fetchPrice('NIFTYBEES.NS')).thenAnswer(
          (_) async => _success('NIFTYBEES.NS', 275.0, currency: 'INR'));
      when(() => mockRepo.updateAssetPrice('mf1', 275.0))
          .thenAnswer((_) async {});

      final result = await service.refreshAllPrices();

      expect(result.updated, 1);
      verify(() => mockYahoo.fetchPrice('NIFTYBEES.NS')).called(1);
      verifyNever(() => mockMutualFund.fetchNav(any()));
    });
  });

  // Each holding is stored in its own currency; a refreshed price has to be
  // written in that currency whatever the quote came in.
  group('prices land in the holding\'s own currency', () {
    ExchangeRateResult fx() => ExchangeRateResult(
          base: 'USD',
          rates: const {'USD': 1.0, 'INR': 83.0, 'EUR': 0.9, 'GBP': 0.8},
          fetchedAt: DateTime.now(),
          success: true,
        );

    /// Records every price written, by asset id.
    Map<String, double> recordWrites() {
      final written = <String, double>{};
      when(() => mockRepo.updateAssetPrice(any(), any()))
          .thenAnswer((inv) async {
        written[inv.positionalArguments[0] as String] =
            inv.positionalArguments[1] as double;
      });
      return written;
    }

    test('crypto is fetched per holding currency, not all in the base',
        () async {
      final inrCoin = MockCoinGeckoService();
      final usdCoin = MockCoinGeckoService();
      final requested = <String>[];
      final perCurrency = PriceUpdateService(
        assetRepository: mockRepo,
        yahooService: mockYahoo,
        stooqService: mockStooq,
        currencyConverter: mockFx,
        goldPriceService: mockGold,
        mutualFundService: mockMutualFund,
        priceCache: mockCache,
        coinGeckoFactory: (vs) {
          requested.add(vs);
          return vs == 'USD' ? usdCoin : inrCoin;
        },
        cryptoFallbackFactory: (_) => mockCryptoCompare,
      );
      when(() => mockRepo.getAllAssets()).thenReturn([
        _makeAsset(id: 'inr', symbol: 'bitcoin', type: AssetType.crypto),
        _makeAsset(
            id: 'usd',
            symbol: 'bitcoin',
            type: AssetType.crypto,
            currency: 'USD'),
      ]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer((_) async => fx());
      when(() => inrCoin.fetchMultiplePrices(any())).thenAnswer(
          (_) async => [_success('bitcoin', 5800000.0)]);
      when(() => usdCoin.fetchMultiplePrices(any())).thenAnswer(
          (_) async => [_success('bitcoin', 70000.0, currency: 'USD')]);
      final written = recordWrites();

      final result = await perCurrency.refreshAllPrices();

      expect(result.updated, 2);
      expect(requested, unorderedEquals(['INR', 'USD']));
      expect(written, {'inr': 5800000.0, 'usd': 70000.0});
    });

    test('a EUR quote is converted for an INR holding (not only USD)',
        () async {
      when(() => mockRepo.getAllAssets()).thenReturn(
          [_makeAsset(id: 's1', symbol: 'SAP.DE', currency: 'INR')]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer((_) async => fx());
      when(() => mockYahoo.fetchPrice('SAP.DE'))
          .thenAnswer((_) async => _success('SAP.DE', 180.0, currency: 'EUR'));
      final written = recordWrites();

      await service.refreshAllPrices();

      expect(written['s1'], closeTo(180.0 / 0.9 * 83.0, 1e-6));
    });

    test('a pence quote is stored in pounds for a GBP holding', () async {
      when(() => mockRepo.getAllAssets()).thenReturn(
          [_makeAsset(id: 's1', symbol: 'VOD.L', currency: 'GBP')]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer((_) async => fx());
      when(() => mockYahoo.fetchPrice('VOD.L'))
          .thenAnswer((_) async => _success('VOD.L', 72.5, currency: 'GBp'));
      final written = recordWrites();

      await service.refreshAllPrices();

      expect(written['s1'], closeTo(0.725, 1e-9));
    });

    test('without live forex a USD quote is never stored as INR', () async {
      when(() => mockRepo.getAllAssets()).thenReturn(
          [_makeAsset(id: 's1', symbol: 'AAPL', currency: 'INR')]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer(
          (_) async => ExchangeRateResult.failure('offline'));
      when(() => mockYahoo.fetchPrice('AAPL'))
          .thenAnswer((_) async => _success('AAPL', 200.0, currency: 'USD'));
      final written = recordWrites();

      final result = await service.refreshAllPrices();

      // Treated like a failed fetch: no cache here, so it counts as failed.
      expect(written, isEmpty);
      expect(result.failed, 1);
      expect(result.errors.single, contains('exchange rate'));
    });

    test('single refresh converts an INR listing for a USD holding',
        () async {
      final asset =
          _makeAsset(id: 's1', symbol: 'TCS.NS', currency: 'USD');
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer((_) async => fx());
      when(() => mockYahoo.fetchPrice('TCS.NS'))
          .thenAnswer((_) async => _success('TCS.NS', 4150.0));
      final written = recordWrites();

      final result = await service.refreshSinglePrice(asset);

      expect(result.currency, 'USD');
      expect(written['s1'], closeTo(4150.0 / 83.0, 1e-9));
    });

    test('a fund NAV is converted for a holding kept outside INR', () async {
      when(() => mockRepo.getAllAssets()).thenReturn([
        _makeAsset(
            id: 'mf1',
            symbol: '120503',
            type: AssetType.mutualFund,
            currency: 'USD'),
      ]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer((_) async => fx());
      when(() => mockMutualFund.fetchNav(120503))
          .thenAnswer((_) async => Ok(_mf(120503, 830.0)));
      final written = recordWrites();

      await service.refreshAllPrices();

      expect(written['mf1'], closeTo(10.0, 1e-9));
    });
  });

  // A fully sold holding stays stored at quantity 0 for its cost basis, but
  // it is closed: nothing to price, and nothing to count.
  group('fully sold holdings', () {
    test('are not refreshed or counted', () async {
      final open = _makeAsset(id: 'open', symbol: 'TCS.NS');
      final sold =
          _makeAsset(id: 'sold', symbol: 'INFY.NS').copyWith(quantity: 0);
      final soldCoin =
          _makeAsset(id: 'coin', symbol: 'bitcoin', type: AssetType.crypto)
              .copyWith(quantity: 0);
      when(() => mockRepo.getAllAssets()).thenReturn([open, sold, soldCoin]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer((_) async => _fxSuccess());
      when(() => mockYahoo.fetchPrice('TCS.NS'))
          .thenAnswer((_) async => _success('TCS.NS', 4000.0));
      when(() => mockRepo.updateAssetPrice(any(), any()))
          .thenAnswer((_) async {});

      final result = await service.refreshAllPrices();

      expect(result.total, 1);
      expect(result.updated, 1);
      expect(result.skipped, 0);
      expect(result.summary, 'Updated 1/1 assets');
      verifyNever(() => mockYahoo.fetchPrice('INFY.NS'));
      verifyNever(() => mockCoinGecko.fetchMultiplePrices(any()));
      verifyNever(() => mockRepo.updateAssetPrice('sold', any()));
    });

    test('a single refresh of a sold holding fetches nothing', () async {
      final sold =
          _makeAsset(id: 'sold', symbol: 'INFY.NS').copyWith(quantity: 0);

      final result = await service.refreshSinglePrice(sold);

      expect(result.success, isFalse);
      verifyNever(() => mockYahoo.fetchPrice(any()));
      verifyNever(() => mockRepo.updateAssetPrice(any(), any()));
    });
  });

  // Two holdings of one symbol in different currencies used to share a
  // bare-symbol cache entry, so offline each could get the other's number.
  group('the offline fallback reads the holding\'s own currency', () {
    Asset coin(String id, String currency) => _makeAsset(
        id: id, symbol: 'bitcoin', type: AssetType.crypto, currency: currency);
    Asset apple(String id, String currency) =>
        _makeAsset(id: id, symbol: 'AAPL', currency: currency);

    /// Cached prices by `symbol:currency`; everything else misses.
    void cacheHolds(Map<String, double> prices) {
      when(() => mockCache.getCachedResult(any(), any())).thenAnswer((inv) {
        final symbol = inv.positionalArguments[0] as String;
        final currency = inv.positionalArguments[1] as String;
        final price = prices[PriceCacheService.keyFor(symbol, currency)];
        return price == null
            ? PriceResult.failure(symbol, 'no cache')
            : _success(symbol, price, currency: currency);
      });
    }

    Map<String, double> recordFallbackWrites() {
      final written = <String, double>{};
      when(() => mockRepo.updateAssetPrice(any(), any(),
          asOf: any(named: 'asOf'))).thenAnswer((inv) async {
        written[inv.positionalArguments[0] as String] =
            inv.positionalArguments[1] as double;
      });
      return written;
    }

    test('crypto held in INR and in USD each get their own cached price',
        () async {
      when(() => mockRepo.getAllAssets())
          .thenReturn([coin('inr', 'INR'), coin('usd', 'USD')]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer((_) async => _fxSuccess());
      when(() => mockCoinGecko.fetchMultiplePrices(any())).thenAnswer(
          (_) async => [PriceResult.failure('bitcoin', 'offline')]);
      cacheHolds({'bitcoin:INR': 5800000.0, 'bitcoin:USD': 70000.0});
      final written = recordFallbackWrites();

      final result = await service.refreshAllPrices();

      expect(result.updated, 2);
      expect(written, {'inr': 5800000.0, 'usd': 70000.0});
    });

    test('a live crypto price is cached under the holding currency',
        () async {
      when(() => mockRepo.getAllAssets()).thenReturn([coin('usd', 'USD')]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer((_) async => _fxSuccess());
      // A provider that labels its quote in lower case still files it
      // under the key the fallback will look for.
      when(() => mockCoinGecko.fetchMultiplePrices(any())).thenAnswer(
          (_) async => [_success('bitcoin', 70000.0, currency: 'usd')]);
      when(() => mockRepo.updateAssetPrice(any(), any()))
          .thenAnswer((_) async {});

      await service.refreshAllPrices();

      final cached = verify(() => mockCache.cachePrice(captureAny()))
          .captured
          .cast<PriceResult>()
          .single;
      expect(PriceCacheService.keyFor(cached.symbol, cached.currency),
          'bitcoin:USD');
    });

    test('a stock held in USD and in INR each get their own cached price',
        () async {
      when(() => mockRepo.getAllAssets())
          .thenReturn([apple('usd', 'USD'), apple('inr', 'INR')]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer((_) async => _fxSuccess());
      when(() => mockYahoo.fetchPrice('AAPL'))
          .thenAnswer((_) async => PriceResult.failure('AAPL', 'offline'));
      cacheHolds({'AAPL:USD': 230.0, 'AAPL:INR': 19205.0});
      final written = recordFallbackWrites();

      final result = await service.refreshAllPrices();

      expect(result.updated, 2);
      expect(written, {'usd': 230.0, 'inr': 19205.0});
    });

    test('with only another currency cached, the holding counts as failed',
        () async {
      when(() => mockRepo.getAllAssets()).thenReturn([apple('inr', 'INR')]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer((_) async => _fxSuccess());
      when(() => mockYahoo.fetchPrice('AAPL'))
          .thenAnswer((_) async => PriceResult.failure('AAPL', 'offline'));
      cacheHolds({'AAPL:USD': 230.0});
      final written = recordFallbackWrites();

      final result = await service.refreshAllPrices();

      expect(result.failed, 1);
      expect(written, isEmpty, reason: r'$230 is not ₹230');
    });
  });
}
