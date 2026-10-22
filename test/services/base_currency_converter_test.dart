import 'package:flutter_test/flutter_test.dart';

import 'package:kashu/services/base_currency_converter.dart';
import 'package:kashu/services/currency_converter_service.dart';

import '../fixtures/sample_portfolio.dart';

void main() {
  group('BaseCurrencyConverter', () {
    test('converts a USD holding into INR at the live rate', () {
      final fx = BaseCurrencyConverter(base: 'INR', rates: sampleRates());
      final apple = samplePortfolio().firstWhere((a) => a.id == 'aapl');

      expect(fx.valueOf(apple), closeTo(8 * 230 * usdInr, 1e-6));
      expect(fx.investedOf(apple), closeTo(8 * 172.5 * usdInr, 1e-6));
    });

    test('leaves base-currency and currency-less amounts untouched', () {
      final fx = BaseCurrencyConverter(base: 'INR', rates: sampleRates());

      expect(fx.convert(1000, 'INR'), 1000);
      expect(fx.convert(1000, ''), 1000);
    });

    test('without live rates, a foreign amount uses the offline rate — '
        'never the raw figure', () {
      const fx = BaseCurrencyConverter(base: 'INR');
      final offline = CurrencyConverterService.fallbackRate('INR');

      expect(fx.convert(100, 'USD'), closeTo(100 * offline, 1e-6));
      expect(
        BaseCurrencyConverter(
          base: 'INR',
          rates: ExchangeRateResult.failure('offline'),
        ).usedFallbackRates,
        isTrue,
      );
    });

    test('loads rates only when a currency differs from the base', () async {
      var loads = 0;
      Future<ExchangeRateResult> load() async {
        loads++;
        return sampleRates();
      }

      final allInr = await BaseCurrencyConverter.forCurrencies(
          ['INR', 'INR', ''],
          base: 'INR',
          loadRates: load);
      expect(allInr.rates, isNull);
      expect(loads, 0);

      final mixed = await BaseCurrencyConverter.forAssets(samplePortfolio(),
          base: 'INR', loadRates: load);
      expect(mixed.rates, isNotNull);
      expect(loads, 1);
    });
  });
}
