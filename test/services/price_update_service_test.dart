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
    when(() => mockCache.getCachedResult(any()))
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
      when(() => mockCache.getCachedResult('RELIANCE.NS')).thenReturn(
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
      verifyNever(() => mockCache.getCachedResult(any()));
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
      when(() => mockCache.getCachedResult('bitcoin'))
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
      verifyNever(() => mockCache.getCachedResult(any()));
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

  group('refreshAllPrices — gold via GoldPriceService', () {
    test('updates gold price with final INR/gram', () async {
      final asset = _makeAsset(
          id: 'g1', type: AssetType.gold, currency: 'INR');
      when(() => mockRepo.getAllAssets()).thenReturn([asset]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer((_) async => _fxSuccess());

      final breakdown = GoldPriceBreakdown(
        usdPerTroyOz: 2400.0,
        usdPerGram: 2400.0 / 31.1035,
        forexRate: 83.5,
        basePerGram: (2400.0 / 31.1035) * 83.5,
        importDutyRate: 0.05,
        aidcRate: 0.01,
        gstRate: 0.03,
        targetCurrency: 'INR',
        usedLiveForex: true,
      );
      when(() => mockGold.fetchGoldPriceBreakdown(
              targetCurrency: any(named: 'targetCurrency')))
          .thenAnswer((_) async => breakdown);
      when(() => mockRepo.updateAssetPrice('g1', any()))
          .thenAnswer((_) async {});

      final result = await service.refreshAllPrices();

      expect(result.updated, 1);
      verify(() => mockRepo.updateAssetPrice('g1', breakdown.finalPerGram))
          .called(1);
    });

    test('uses cache fallback when gold API fails', () async {
      final asset = _makeAsset(
          id: 'g1', type: AssetType.gold, currency: 'INR');
      when(() => mockRepo.getAllAssets()).thenReturn([asset]);
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockFx.fetchRates()).thenAnswer((_) async => _fxSuccess());
      when(() => mockGold.fetchGoldPriceBreakdown(
              targetCurrency: any(named: 'targetCurrency')))
          .thenAnswer((_) async => null);
      when(() => mockCache.getCachedResult(PriceSymbols.goldComex))
          .thenReturn(_success(PriceSymbols.goldComex, 6500.0));
      when(() => mockRepo.updateAssetPrice('g1', 6500.0,
          asOf: any(named: 'asOf'))).thenAnswer((_) async {});

      final result = await service.refreshAllPrices();

      expect(result.updated, 1);
      verify(() => mockRepo.updateAssetPrice('g1', 6500.0,
          asOf: any(named: 'asOf'))).called(1);
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

    test('returns cached result when stock refresh fails', () async {
      final asset = _makeAsset(
          id: 's1', symbol: 'FAIL.NS', type: AssetType.stock, currency: 'INR');
      when(() => mockRepo.getBaseCurrency()).thenReturn('INR');
      when(() => mockYahoo.fetchPrice('FAIL.NS'))
          .thenAnswer((_) async =>
              PriceResult.failure('FAIL.NS', 'not found'));
      when(() => mockCache.getCachedResult('FAIL.NS'))
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
      when(() => mockCache.getCachedResult('120503'))
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
}
