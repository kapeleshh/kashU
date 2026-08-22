import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

import 'package:kashu/services/stooq_service.dart';

class MockHttpClient extends Mock implements http.Client {}

const _csvHeader = 'Symbol,Date,Time,Open,High,Low,Close,Volume';

void main() {
  late MockHttpClient client;
  late StooqService service;

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  setUp(() {
    client = MockHttpClient();
    service = StooqService(client: client);
  });

  void stubBody(String body, {int statusCode = 200}) {
    when(() => client.get(any(), headers: any(named: 'headers')))
        .thenAnswer((_) async => http.Response(body, statusCode));
  }

  Uri capturedUri() =>
      verify(() => client.get(captureAny(), headers: any(named: 'headers')))
          .captured
          .single as Uri;

  group('fetchPrice', () {
    test('parses the Close column and infers INR for .NS symbols', () async {
      stubBody('$_csvHeader\n'
          'RELIANCE.NS,2024-01-15,15:30:00,2450.00,2480.00,2440.00,2465.50,1234567');

      final result = await service.fetchPrice('RELIANCE.NS');

      expect(result.success, isTrue);
      expect(result.price, 2465.50);
      expect(result.currency, 'INR');
      expect(capturedUri().toString(), contains('s=reliance.ns'));
    });

    test('maps plain US tickers to the .us suffix with USD', () async {
      stubBody('$_csvHeader\n'
          'AAPL.US,2024-01-15,22:00:00,180.0,186.0,179.5,184.20,999');

      final result = await service.fetchPrice('AAPL');

      expect(result.success, isTrue);
      expect(result.currency, 'USD');
      expect(capturedUri().toString(), contains('s=aapl.us'));
    });

    test('maps COMEX futures GC=F to gc.f', () async {
      stubBody('$_csvHeader\n'
          'GC.F,2024-01-15,22:00:00,2395.0,2410.0,2390.0,2400.50,111');

      final result = await service.fetchPrice('GC=F');

      expect(result.success, isTrue);
      expect(result.price, 2400.50);
      expect(result.currency, 'USD');
      expect(capturedUri().toString(), contains('s=gc.f'));
    });

    test('N/D values (unknown symbol) are a failure', () async {
      stubBody('$_csvHeader\n'
          'FAKE.US,N/D,N/D,N/D,N/D,N/D,N/D,N/D');

      final result = await service.fetchPrice('FAKE');

      expect(result.success, isFalse);
      expect(result.error, contains('no valid price'));
    });

    test('header-only response is a failure', () async {
      stubBody(_csvHeader);

      final result = await service.fetchPrice('AAPL');

      expect(result.success, isFalse);
    });

    test('non-200 status is a failure', () async {
      stubBody('service unavailable', statusCode: 503);

      final result = await service.fetchPrice('AAPL');

      expect(result.success, isFalse);
      expect(result.error, contains('503'));
    });
  });
}
