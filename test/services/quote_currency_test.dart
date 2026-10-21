import 'package:flutter_test/flutter_test.dart';

import 'package:kashu/services/currency_converter_service.dart';
import 'package:kashu/services/quote_currency.dart';

ExchangeRateResult _rates(Map<String, double> rates, {bool success = true}) =>
    ExchangeRateResult(
      base: 'USD',
      rates: rates,
      fetchedAt: DateTime(2024, 1, 1),
      success: success,
    );

final _live = _rates({'INR': 83.0, 'EUR': 0.9, 'GBP': 0.8, 'HKD': 7.8});

void main() {
  group('QuoteCurrency.normalize', () {
    test('moves London pence (GBp / GBX) into pounds', () {
      expect(QuoteCurrency.normalize(250, 'GBp'),
          (price: 2.5, currency: 'GBP'));
      expect(QuoteCurrency.normalize(250, 'GBX'),
          (price: 2.5, currency: 'GBP'));
    });

    test('leaves a major-unit quote alone (GBP is not pence)', () {
      expect(QuoteCurrency.normalize(250, 'GBP'),
          (price: 250.0, currency: 'GBP'));
      expect(QuoteCurrency.normalize(10, 'usd'),
          (price: 10.0, currency: 'USD'));
    });
  });

  group('QuoteCurrency.plan', () {
    test('a quote already in the selected currency is used as is', () {
      final plan = QuoteCurrency.plan(
          quotePrice: 2850, quoteCurrency: 'INR', selectedCurrency: 'INR');

      expect(plan.action, AutofillAction.asQuoted);
      expect(plan.currency, 'INR');
      expect(plan.price, 2850);
    });

    test('AAPL in an INR form moves the field to USD, price untouched', () {
      // The bug: 200 (USD) landed in a field still saying INR.
      final plan = QuoteCurrency.plan(
          quotePrice: 200, quoteCurrency: 'USD', selectedCurrency: 'INR');

      expect(plan.action, AutofillAction.adoptQuoteCurrency);
      expect(plan.currency, 'USD');
      expect(plan.price, 200);
    });

    test('a pence quote adopts GBP in pounds', () {
      final plan = QuoteCurrency.plan(
          quotePrice: 1234, quoteCurrency: 'GBp', selectedCurrency: 'INR');

      expect(plan.action, AutofillAction.adoptQuoteCurrency);
      expect(plan.currency, 'GBP');
      expect(plan.price, closeTo(12.34, 1e-9));
    });

    test('a currency the user chose is kept and the price converted', () {
      final plan = QuoteCurrency.plan(
        quotePrice: 200,
        quoteCurrency: 'USD',
        selectedCurrency: 'INR',
        currencyChosenByUser: true,
        rates: _live,
      );

      expect(plan.action, AutofillAction.converted);
      expect(plan.currency, 'INR');
      expect(plan.price, closeTo(200 * 83.0, 1e-6));
    });

    test('an unsupported quote currency is converted into the selection', () {
      final plan = QuoteCurrency.plan(
        quotePrice: 390,
        quoteCurrency: 'HKD',
        selectedCurrency: 'INR',
        rates: _live,
      );

      expect(plan.action, AutofillAction.converted);
      expect(plan.currency, 'INR');
      expect(plan.price, closeTo(390 / 7.8 * 83.0, 1e-6));
    });

    test('with no live rate it asks for a manual price, never guesses', () {
      for (final rates in [
        null,
        _rates({}, success: false),
        _rates({'INR': 83.0}), // no HKD rate
      ]) {
        final plan = QuoteCurrency.plan(
          quotePrice: 390,
          quoteCurrency: 'HKD',
          selectedCurrency: 'INR',
          rates: rates,
        );

        expect(plan.action, AutofillAction.needsManualPrice, reason: '$rates');
        expect(plan.currency, 'INR');
        expect(plan.price, isNull);
      }
    });

    test('a quote with no currency is not trusted', () {
      final plan = QuoteCurrency.plan(
          quotePrice: 10, quoteCurrency: '', selectedCurrency: 'INR');

      expect(plan.action, AutofillAction.needsManualPrice);
    });

    test('the stored price and the currency field always agree', () {
      // Whatever the plan, its price is denominated in its own currency.
      for (final quote in [('USD', 200.0), ('GBp', 500.0), ('HKD', 39.0)]) {
        for (final selected in ['INR', 'USD', 'EUR']) {
          for (final chosen in [false, true]) {
            final plan = QuoteCurrency.plan(
              quotePrice: quote.$2,
              quoteCurrency: quote.$1,
              selectedCurrency: selected,
              currencyChosenByUser: chosen,
              rates: _live,
            );
            final expected = QuoteCurrency.convert(
                quote.$2, quote.$1, plan.currency, _live);
            expect(plan.price, closeTo(expected!, 1e-9),
                reason: '$quote into $selected (chosen: $chosen)');
          }
        }
      }
    });
  });

  group('QuoteCurrency.convert', () {
    test('converts between two non-USD currencies via the USD base', () {
      expect(QuoteCurrency.convert(90, 'EUR', 'INR', _live),
          closeTo(90 / 0.9 * 83.0, 1e-9));
    });

    test('is identity for the same currency, even without rates', () {
      expect(QuoteCurrency.convert(42, 'INR', 'INR', null), 42);
      expect(QuoteCurrency.convert(4200, 'GBp', 'GBP', null), 42);
    });
  });
}
