import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

import 'package:kashu/data/models/asset_type.dart';
import 'package:kashu/services/cryptocompare_service.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  late MockHttpClient client;
  late CryptoCompareService service;

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  setUp(() {
    client = MockHttpClient();
    service = CryptoCompareService(client: client, vsCurrency: 'inr');
  });

  void stubResponse(String body, {int statusCode = 200}) {
    when(() => client.get(any(), headers: any(named: 'headers')))
        .thenAnswer((_) async => http.Response(body, statusCode));
  }

  group('supportsAssetType', () {
    test('supports only crypto', () {
      expect(service.supportsAssetType(AssetType.crypto), isTrue);
      expect(service.supportsAssetType(AssetType.stock), isFalse);
      expect(service.supportsAssetType(AssetType.gold), isFalse);
    });
  });

  group('fetchPrice', () {
    test('maps CoinGecko id to ticker and parses the price', () async {
      stubResponse('{"INR": 5800000.5}');

      final result = await service.fetchPrice('bitcoin');

      expect(result.success, isTrue);
      expect(result.price, 5800000.5);
      expect(result.currency, 'INR');
      final uri = verify(() =>
              client.get(captureAny(), headers: any(named: 'headers')))
          .captured
          .single as Uri;
      expect(uri.toString(), contains('fsym=BTC'));
      expect(uri.toString(), contains('tsyms=INR'));
    });

    test('unmapped CoinGecko id fails without a network call', () async {
      final result = await service.fetchPrice('some-obscure-memecoin');

      expect(result.success, isFalse);
      expect(result.error, contains('No CryptoCompare mapping'));
      verifyNever(() => client.get(any(), headers: any(named: 'headers')));
    });

    test('HTTP 200 with Response:Error body is treated as failure', () async {
      stubResponse(
          '{"Response":"Error","Message":"fsym param seems invalid."}');

      final result = await service.fetchPrice('bitcoin');

      expect(result.success, isFalse);
      expect(result.error, contains('fsym param seems invalid'));
    });

    test('does not retry on 429 rate limit', () async {
      stubResponse('rate limited', statusCode: 429);

      final result = await service.fetchPrice('bitcoin');

      expect(result.success, isFalse);
      expect(result.error, contains('Rate limit'));
      verify(() => client.get(any(), headers: any(named: 'headers')))
          .called(1);
    });
  });

  group('fetchMultiplePrices', () {
    test('parses pricemulti and keeps input order, unmapped ids fail',
        () async {
      stubResponse('{"BTC": {"INR": 5800000.0}, "ETH": {"INR": 310000.0}}');

      final results = await service.fetchMultiplePrices(
          ['bitcoin', 'not-a-real-coin', 'ethereum']);

      expect(results, hasLength(3));
      expect(results[0].success, isTrue);
      expect(results[0].price, 5800000.0);
      expect(results[1].success, isFalse);
      expect(results[1].error, contains('No CryptoCompare mapping'));
      expect(results[2].success, isTrue);
      expect(results[2].price, 310000.0);
    });

    test('all-unmapped input fails every symbol without a network call',
        () async {
      final results =
          await service.fetchMultiplePrices(['fake-coin-a', 'fake-coin-b']);

      expect(results.every((r) => !r.success), isTrue);
      verifyNever(() => client.get(any(), headers: any(named: 'headers')));
    });

    test('error body fails every symbol', () async {
      stubResponse('{"Response":"Error","Message":"nope"}');

      final results =
          await service.fetchMultiplePrices(['bitcoin', 'ethereum']);

      expect(results.every((r) => !r.success), isTrue);
      expect(results.first.error, contains('nope'));
    });
  });
}
