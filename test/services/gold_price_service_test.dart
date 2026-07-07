import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kashu/services/currency_converter_service.dart';
import 'package:kashu/services/gold_price_service.dart';
import 'package:kashu/services/price_service.dart';
import 'package:kashu/services/stooq_service.dart';
import 'package:kashu/services/yahoo_finance_service.dart';
import 'package:kashu/data/models/asset_type.dart';

class MockYahooFinanceService extends Mock implements YahooFinanceService {}

class MockStooqService extends Mock implements StooqService {}

class MockCurrencyConverterService extends Mock
    implements CurrencyConverterService {}

/// A successful Yahoo Finance result for the given symbol/price.
PriceResult _yahooSuccess(String symbol, double price,
    {String currency = 'USD'}) {
  return PriceResult(
    symbol: symbol,
    price: price,
    currency: currency,
    fetchedAt: DateTime.now(),
    success: true,
  );
}

/// A successful ExchangeRateResult with the given rates.
ExchangeRateResult _fxSuccess(Map<String, double> rates) {
  return ExchangeRateResult(
    base: 'USD',
    rates: rates,
    fetchedAt: DateTime.now(),
    success: true,
  );
}

void main() {
  late MockYahooFinanceService mockYahoo;
  late MockStooqService mockStooq;
  late MockCurrencyConverterService mockFx;
  late GoldPriceService service;

  setUp(() {
    mockYahoo = MockYahooFinanceService();
    mockStooq = MockStooqService();
    mockFx = MockCurrencyConverterService();

    // Default: Stooq fallback fails too (individual tests override)
    when(() => mockStooq.fetchPrice(any())).thenAnswer(
        (inv) async => PriceResult.failure(
            inv.positionalArguments.first as String, 'stooq unavailable'));

    service = GoldPriceService(
      yahooService: mockYahoo,
      stooqService: mockStooq,
      currencyConverter: mockFx,
    );
  });

  group('GoldPriceService.supportsAssetType', () {
    test('returns true for gold', () {
      expect(service.supportsAssetType(AssetType.gold), true);
    });

    test('returns false for non-gold types', () {
      for (final type in AssetType.values) {
        if (type != AssetType.gold) {
          expect(service.supportsAssetType(type), false,
              reason: '${type.name} should not be supported');
        }
      }
    });
  });

  group('GoldPriceService.fetchGoldPriceBreakdown', () {
    const usdPerTroyOz = 2400.0; // ~typical 2024 gold price
    const inrPerUsd = 83.5;

    test('returns correct breakdown for INR with Indian taxes', () async {
      when(() => mockYahoo.fetchPrice(PriceSymbols.goldComex))
          .thenAnswer((_) async => _yahooSuccess('GC=F', usdPerTroyOz));
      when(() => mockFx.fetchRates())
          .thenAnswer((_) async => _fxSuccess({'INR': inrPerUsd}));

      final breakdown = await service.fetchGoldPriceBreakdown(
        targetCurrency: 'INR',
      );

      expect(breakdown, isNotNull);
      expect(breakdown!.usdPerTroyOz, usdPerTroyOz);
      expect(breakdown.targetCurrency, 'INR');

      // usdPerGram = 2400 / 31.1035 ≈ 77.16
      expect(breakdown.usdPerGram,
          closeTo(usdPerTroyOz / CurrencyConverterService.gramsPerTroyOz, 0.01));

      // basePerGram = usdPerGram * 83.5
      final expectedBase = breakdown.usdPerGram * inrPerUsd;
      expect(breakdown.basePerGram, closeTo(expectedBase, 0.01));

      // Indian tax: BCD 5% + AIDC 1% + GST 3%
      expect(breakdown.importDutyRate, GoldTaxConfig.india.importDutyRate);
      expect(breakdown.aidcRate, GoldTaxConfig.india.aidcRate);
      expect(breakdown.gstRate, GoldTaxConfig.india.gstRate);

      // finalPerGram = basePerGram * (1+0.05+0.01) * (1+0.03)
      final expectedFinal =
          expectedBase * GoldTaxConfig.india.totalTaxMultiplier;
      expect(breakdown.finalPerGram, closeTo(expectedFinal, 0.01));
    });

    test('returns USD breakdown with no taxes applied', () async {
      when(() => mockYahoo.fetchPrice(PriceSymbols.goldComex))
          .thenAnswer((_) async => _yahooSuccess('GC=F', usdPerTroyOz));

      final breakdown = await service.fetchGoldPriceBreakdown(
        targetCurrency: 'USD',
        taxConfig: GoldTaxConfig.none,
      );

      expect(breakdown, isNotNull);
      expect(breakdown!.targetCurrency, 'USD');
      expect(breakdown.importDutyRate, 0.0);
      expect(breakdown.aidcRate, 0.0);
      expect(breakdown.gstRate, 0.0);
      // finalPerGram == basePerGram when no tax
      expect(breakdown.finalPerGram, closeTo(breakdown.basePerGram, 0.01));
    });

    test('returns null when both Yahoo and the Stooq fallback fail',
        () async {
      when(() => mockYahoo.fetchPrice(any()))
          .thenAnswer((_) async =>
              PriceResult.failure('GC=F', 'Yahoo unavailable'));

      final breakdown = await service.fetchGoldPriceBreakdown();

      expect(breakdown, isNull);
      verify(() => mockStooq.fetchPrice(PriceSymbols.goldComex)).called(1);
    });

    test('falls back to Stooq when Yahoo fails — same tax pipeline',
        () async {
      when(() => mockYahoo.fetchPrice(any()))
          .thenAnswer((_) async =>
              PriceResult.failure('GC=F', 'Yahoo unavailable'));
      when(() => mockStooq.fetchPrice(PriceSymbols.goldComex))
          .thenAnswer((_) async => _yahooSuccess('GC=F', usdPerTroyOz));
      when(() => mockFx.fetchRates())
          .thenAnswer((_) async => _fxSuccess({'INR': inrPerUsd}));

      final breakdown = await service.fetchGoldPriceBreakdown(
        targetCurrency: 'INR',
      );

      // The Stooq quote feeds the identical oz→gram→forex→tax math,
      // including Indian duties for INR.
      expect(breakdown, isNotNull);
      expect(breakdown!.usdPerTroyOz, usdPerTroyOz);
      final expectedBase = (usdPerTroyOz / 31.1035) * inrPerUsd;
      expect(breakdown.basePerGram, closeTo(expectedBase, 0.01));
      expect(breakdown.finalPerGram,
          closeTo(expectedBase * (1 + 0.05 + 0.01) * (1 + 0.03), 0.01));
    });

    test('uses live forex rate when available', () async {
      when(() => mockYahoo.fetchPrice(PriceSymbols.goldComex))
          .thenAnswer((_) async => _yahooSuccess('GC=F', usdPerTroyOz));
      when(() => mockFx.fetchRates())
          .thenAnswer((_) async => _fxSuccess({'INR': inrPerUsd}));

      final breakdown = await service.fetchGoldPriceBreakdown(
        targetCurrency: 'INR',
      );

      expect(breakdown!.usedLiveForex, true);
      expect(breakdown.forexRate, inrPerUsd);
    });

    test('falls back to hardcoded rate when forex API fails', () async {
      when(() => mockYahoo.fetchPrice(PriceSymbols.goldComex))
          .thenAnswer((_) async => _yahooSuccess('GC=F', usdPerTroyOz));
      when(() => mockFx.fetchRates())
          .thenAnswer((_) async =>
              ExchangeRateResult.failure('network error'));

      final breakdown = await service.fetchGoldPriceBreakdown(
        targetCurrency: 'INR',
      );

      expect(breakdown, isNotNull);
      expect(breakdown!.usedLiveForex, false);
      expect(breakdown.forexRate,
          CurrencyConverterService.fallbackRate('INR'));
    });
  });

  group('GoldPriceService.fetchSilverPriceBreakdown', () {
    test('applies silver tax rates (10% BCD + 3% GST)', () async {
      when(() => mockYahoo.fetchPrice(PriceSymbols.silverComex))
          .thenAnswer((_) async => _yahooSuccess('SI=F', 30.0));
      when(() => mockFx.fetchRates())
          .thenAnswer((_) async => _fxSuccess({'INR': 83.5}));

      final breakdown = await service.fetchSilverPriceBreakdown(
        targetCurrency: 'INR',
      );

      expect(breakdown, isNotNull);
      expect(breakdown!.importDutyRate, GoldTaxConfig.silver.importDutyRate);
      expect(breakdown.aidcRate, GoldTaxConfig.silver.aidcRate);
      expect(breakdown.gstRate, GoldTaxConfig.silver.gstRate);
    });
  });

  group('GoldTaxConfig', () {
    test('india effective tax ≈ 9.18%', () {
      expect(GoldTaxConfig.india.effectiveTaxPercent, closeTo(9.18, 0.1));
    });

    test('none has zero tax and multiplier of 1.0', () {
      expect(GoldTaxConfig.none.totalTaxMultiplier, closeTo(1.0, 0.0001));
      expect(GoldTaxConfig.none.effectiveTaxPercent, closeTo(0.0, 0.0001));
    });

    test('silver total tax multiplier is correct', () {
      // (1 + 0.10 + 0) * (1 + 0.03) = 1.10 * 1.03 = 1.133
      expect(GoldTaxConfig.silver.totalTaxMultiplier, closeTo(1.133, 0.001));
    });
  });

  group('GoldPriceBreakdown computed properties', () {
    test('taxAmountPerGram = finalPerGram - basePerGram', () async {
      when(() => mockYahoo.fetchPrice(PriceSymbols.goldComex))
          .thenAnswer((_) async => _yahooSuccess('GC=F', 2400.0));
      when(() => mockFx.fetchRates())
          .thenAnswer((_) async => _fxSuccess({'INR': 83.5}));

      final breakdown =
          await service.fetchGoldPriceBreakdown(targetCurrency: 'INR');

      expect(breakdown!.taxAmountPerGram,
          closeTo(breakdown.finalPerGram - breakdown.basePerGram, 0.01));
    });

    test('effectiveTaxPercent matches manual formula', () {
      final config = GoldTaxConfig.india;
      final expected = (config.totalTaxMultiplier - 1) * 100;
      expect(config.effectiveTaxPercent, closeTo(expected, 0.0001));
    });
  });
}
