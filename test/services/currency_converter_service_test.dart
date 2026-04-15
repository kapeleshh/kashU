import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:kashu/services/currency_converter_service.dart';

class MockHttpClient extends Mock implements http.Client {}

/// A minimal successful Open Exchange Rates JSON payload.
String _successBody(Map<String, double> rates) => jsonEncode({
      'result': 'success',
      'base_code': 'USD',
      'rates': rates,
    });

void main() {
  setUpAll(() {
    registerFallbackValue(Uri.parse('http://fallback.test'));
  });

  group('CurrencyConverterService.fetchRates', () {
    late MockHttpClient mockClient;
    late CurrencyConverterService service;

    setUp(() {
      mockClient = MockHttpClient();
      service = CurrencyConverterService(client: mockClient);
    });

    test('returns rates on HTTP 200 success', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(
                _successBody({'INR': 83.5, 'EUR': 0.92, 'GBP': 0.79}),
                200,
              ));

      final result = await service.fetchRates();

      expect(result.success, true);
      expect(result.base, 'USD');
      expect(result.rates['INR'], 83.5);
      expect(result.rates['EUR'], 0.92);
    });

    test('returns failure on non-200 HTTP status', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('Not Found', 404));

      final result = await service.fetchRates();

      expect(result.success, false);
      expect(result.error, contains('404'));
    });

    test('returns failure when API result is not success', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(
                jsonEncode({'result': 'error', 'rates': {}}),
                200,
              ));

      final result = await service.fetchRates();

      expect(result.success, false);
    });

    test('returns failure on network error', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenThrow(http.ClientException('connection refused'));

      final result = await service.fetchRates();

      expect(result.success, false);
      expect(result.error, contains('connection refused'));
    });

    test('caches result and does not call network on second fetch', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(
                _successBody({'INR': 83.5}),
                200,
              ));

      await service.fetchRates();
      await service.fetchRates(); // second call — should use cache

      // Only one real HTTP call despite two fetchRates() calls
      verify(() => mockClient.get(any(), headers: any(named: 'headers')))
          .called(1);
    });

    test('forceRefresh bypasses cache', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(
                _successBody({'INR': 83.5}),
                200,
              ));

      await service.fetchRates();
      await service.fetchRates(forceRefresh: true);

      verify(() => mockClient.get(any(), headers: any(named: 'headers')))
          .called(2);
    });
  });

  group('ExchangeRateResult', () {
    const rates = {'INR': 83.5, 'EUR': 0.92, 'GBP': 0.79};
    final result = ExchangeRateResult(
      base: 'USD',
      rates: rates,
      fetchedAt: DateTime.now(),
      success: true,
    );

    test('getRate returns 1.0 for base currency', () {
      expect(result.getRate('USD'), 1.0);
    });

    test('getRate returns correct rate for known currency', () {
      expect(result.getRate('INR'), 83.5);
    });

    test('getRate returns 1.0 for unknown currency', () {
      expect(result.getRate('XYZ'), 1.0);
    });

    test('convert multiplies amount by rate', () {
      expect(result.convert(100.0, 'INR'), closeTo(8350.0, 0.01));
    });

    test('ExchangeRateResult.failure has success=false', () {
      final failure = ExchangeRateResult.failure('some error');
      expect(failure.success, false);
      expect(failure.error, 'some error');
      expect(failure.rates, isEmpty);
    });
  });

  group('CurrencyConverterService.fallbackRate', () {
    test('INR fallback is approximately 83–84', () {
      final rate = CurrencyConverterService.fallbackRate('INR');
      expect(rate, greaterThan(80.0));
      expect(rate, lessThan(90.0));
    });

    test('EUR fallback is between 0.85 and 0.99', () {
      final rate = CurrencyConverterService.fallbackRate('EUR');
      expect(rate, greaterThan(0.85));
      expect(rate, lessThan(0.99));
    });

    test('unknown currency fallback is 1.0', () {
      expect(CurrencyConverterService.fallbackRate('XYZ'), 1.0);
    });

    test('all supported currencies have a non-zero fallback', () {
      const currencies = [
        'INR', 'EUR', 'GBP', 'JPY', 'AED', 'SGD', 'AUD', 'CAD', 'CHF'
      ];
      for (final c in currencies) {
        expect(CurrencyConverterService.fallbackRate(c), greaterThan(0),
            reason: '$c fallback should be > 0');
      }
    });
  });

  group('CurrencyConverterService.convertFromUSD', () {
    test('returns input unchanged for USD → USD', () async {
      final service = CurrencyConverterService(client: MockHttpClient());
      final result = await service.convertFromUSD(100.0, 'USD');
      expect(result, 100.0);
    });

    test('uses fallback rate when network fails', () async {
      final mockClient = MockHttpClient();
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenThrow(http.ClientException('no internet'));

      final service = CurrencyConverterService(client: mockClient);
      final result = await service.convertFromUSD(100.0, 'INR');

      // Should use fallback rate ~83.5
      expect(result, closeTo(100.0 * CurrencyConverterService.fallbackRate('INR'), 1.0));
    });
  });
}
