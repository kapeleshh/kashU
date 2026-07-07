import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

import 'package:kashu/services/yahoo_finance_service.dart';

class MockHttpClient extends Mock implements http.Client {}

/// A minimal valid Yahoo chart response.
String chartBody(double price, {String currency = 'INR'}) => '''
{"chart":{"result":[{"meta":{"regularMarketPrice":$price,"currency":"$currency"}}],"error":null}}''';

void main() {
  late MockHttpClient client;
  late YahooFinanceService service;

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  setUp(() {
    client = MockHttpClient();
    service = YahooFinanceService(client: client);
  });

  void stubHost(String host, http.Response response) {
    when(() => client.get(any(that: predicate<Uri>((u) => u.host == host)),
            headers: any(named: 'headers')))
        .thenAnswer((_) async => response);
  }

  group('fetchPrice', () {
    test('parses price and currency from the chart payload', () async {
      stubHost('query1.finance.yahoo.com',
          http.Response(chartBody(2465.5, currency: 'INR'), 200));

      final result = await service.fetchPrice('RELIANCE.NS');

      expect(result.success, isTrue);
      expect(result.price, 2465.5);
      expect(result.currency, 'INR');
    });

    test('fails over to query2 when query1 returns non-200', () async {
      stubHost('query1.finance.yahoo.com', http.Response('gone', 404));
      stubHost('query2.finance.yahoo.com',
          http.Response(chartBody(184.2, currency: 'USD'), 200));

      final result = await service.fetchPrice('AAPL');

      expect(result.success, isTrue);
      expect(result.price, 184.2);
      verify(() => client.get(
          any(that: predicate<Uri>(
              (u) => u.host == 'query2.finance.yahoo.com')),
          headers: any(named: 'headers'))).called(1);
    });

    test('returns failure when both hosts return errors', () async {
      stubHost('query1.finance.yahoo.com', http.Response('gone', 404));
      stubHost('query2.finance.yahoo.com', http.Response('gone', 500));

      final result = await service.fetchPrice('NOPE.NS');

      expect(result.success, isFalse);
      expect(result.error, contains('404'));
    });

    test('malformed JSON is a failure, not a crash', () async {
      stubHost('query1.finance.yahoo.com',
          http.Response('<html>maintenance</html>', 200));
      stubHost('query2.finance.yahoo.com',
          http.Response('<html>maintenance</html>', 200));

      final result = await service.fetchPrice('AAPL');

      expect(result.success, isFalse);
    });

    test('missing/zero price in an otherwise valid payload fails', () async {
      stubHost(
          'query1.finance.yahoo.com',
          http.Response(
              '{"chart":{"result":[{"meta":{"currency":"USD"}}]}}', 200));
      stubHost('query2.finance.yahoo.com',
          http.Response(chartBody(0, currency: 'USD'), 200));

      final result = await service.fetchPrice('AAPL');

      expect(result.success, isFalse);
    });

    test('empty symbol fails without a network call', () async {
      final result = await service.fetchPrice('  ');

      expect(result.success, isFalse);
      expect(result.error, contains('Symbol is empty'));
      verifyNever(() => client.get(any(), headers: any(named: 'headers')));
    });
  });
}
