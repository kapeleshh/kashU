import 'package:flutter_test/flutter_test.dart';
import 'package:kashu/core/utils/currency_formatter.dart';
import 'package:kashu/services/currency_converter_service.dart';

ExchangeRateResult _rates(Map<String, double> r) => ExchangeRateResult(
      base: 'USD',
      rates: {'USD': 1.0, ...r},
      fetchedAt: DateTime(2024),
      success: true,
    );

void main() {
  group('ExchangeRateResult.convertBetween', () {
    final rates = _rates({'INR': 80.0, 'EUR': 0.5});

    test('same currency is identity', () {
      expect(rates.convertBetween(100, 'INR', 'INR'), 100);
      expect(rates.convertBetween(100, 'USD', 'USD'), 100);
    });

    test('converts via the USD base (INR → USD)', () {
      // 800 INR / 80 = 10 USD
      expect(rates.convertBetween(800, 'INR', 'USD'), closeTo(10, 1e-9));
    });

    test('converts USD → INR', () {
      expect(rates.convertBetween(10, 'USD', 'INR'), closeTo(800, 1e-9));
    });

    test('converts between two non-USD currencies (INR → EUR)', () {
      // 800 INR → 10 USD → 5 EUR
      expect(rates.convertBetween(800, 'INR', 'EUR'), closeTo(5, 1e-9));
    });

    test('a failed result falls back to static rates, never returns garbage',
        () {
      final failed = ExchangeRateResult.failure('offline');
      // Uses CurrencyConverterService.fallbackRate (INR ≈ 83.5).
      final usd = failed.convertBetween(835, 'INR', 'USD');
      expect(usd, closeTo(10, 0.5));
      // Same currency is still identity even on failure.
      expect(failed.convertBetween(50, 'INR', 'INR'), 50);
    });

    test('a missing currency falls back instead of dividing by zero', () {
      final partial = _rates({'INR': 80.0}); // no EUR in the map
      final out = partial.convertBetween(800, 'INR', 'EUR');
      expect(out.isFinite, isTrue);
      expect(out, greaterThan(0));
    });
  });

  group('CurrencyFormatter.formatCompactCurrency', () {
    test('INR uses the Cr/L/K scale', () {
      expect(CurrencyFormatter.formatCompactCurrency(12500000, 'INR'),
          '₹1.25Cr');
      expect(CurrencyFormatter.formatCompactCurrency(150000, 'INR'), '₹1.50L');
      expect(CurrencyFormatter.formatCompactCurrency(2500, 'INR'), '₹2.50K');
    });

    test('non-INR uses the K/M/B scale', () {
      expect(CurrencyFormatter.formatCompactCurrency(2500, 'USD'), r'$2.50K');
      expect(
          CurrencyFormatter.formatCompactCurrency(3000000, 'USD'), r'$3.00M');
      expect(CurrencyFormatter.formatCompactCurrency(4000000000, 'USD'),
          r'$4.00B');
    });

    test('negative amounts keep the sign', () {
      expect(CurrencyFormatter.formatCompactCurrency(-150000, 'INR'),
          '-₹1.50L');
    });

    test('below 1000 falls back to full formatting', () {
      expect(CurrencyFormatter.formatCompactCurrency(500, 'USD'),
          CurrencyFormatter.formatCurrency(500, 'USD'));
    });
  });
}
