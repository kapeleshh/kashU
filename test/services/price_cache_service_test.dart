import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:kashu/core/constants/app_constants.dart';
import 'package:kashu/services/price_cache_service.dart';
import 'package:kashu/services/price_service.dart';

void main() {
  late Directory tempDir;
  late PriceCacheService cache;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kashu_price_cache_test');
    Hive.init(tempDir.path);
    await Hive.openBox(AppConstants.priceCacheBox);
    cache = PriceCacheService();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  Future<void> cacheAt(String symbol, double price, DateTime fetchedAt) {
    return cache.cachePrice(PriceResult(
      symbol: symbol,
      price: price,
      currency: 'INR',
      fetchedAt: fetchedAt,
      success: true,
    ));
  }

  group('getCachedResult', () {
    test('fresh entry (within TTL) is served without the stale flag',
        () async {
      final fetchedAt = DateTime.now().subtract(const Duration(minutes: 5));
      await cacheAt('AAPL', 200.0, fetchedAt);

      final result = cache.getCachedResult('AAPL', 'INR');

      expect(result.success, isTrue);
      expect(result.price, 200.0);
      expect(result.isStale, isFalse);
    });

    test('entry older than the TTL but within 7 days is served as stale, '
        'keeping its original fetch time', () async {
      final fetchedAt = DateTime.now().subtract(const Duration(days: 2));
      await cacheAt('AAPL', 195.0, fetchedAt);

      final result = cache.getCachedResult('AAPL', 'INR');

      expect(result.success, isTrue);
      expect(result.price, 195.0);
      expect(result.isStale, isTrue);
      expect(result.fetchedAt.difference(fetchedAt).inSeconds.abs(),
          lessThan(2));
    });

    test('entry older than 7 days is treated as missing', () async {
      final fetchedAt = DateTime.now().subtract(const Duration(days: 8));
      await cacheAt('AAPL', 180.0, fetchedAt);

      final result = cache.getCachedResult('AAPL', 'INR');

      expect(result.success, isFalse);
      expect(result.error, contains('older than'));
    });

    test('a custom maxAge bound is respected', () async {
      final fetchedAt = DateTime.now().subtract(const Duration(hours: 3));
      await cacheAt('AAPL', 190.0, fetchedAt);

      expect(
        cache
            .getCachedResult('AAPL', 'INR', maxAge: const Duration(hours: 1))
            .success,
        isFalse,
      );
      expect(
        cache
            .getCachedResult('AAPL', 'INR', maxAge: const Duration(hours: 6))
            .success,
        isTrue,
      );
    });

    test('missing symbol returns a failure', () {
      final result = cache.getCachedResult('UNKNOWN', 'INR');
      expect(result.success, isFalse);
      expect(result.error, contains('No cached price'));
    });

    test('corrupt entry returns a failure instead of throwing', () async {
      await Hive.box(AppConstants.priceCacheBox)
          .put(PriceCacheService.keyFor('BROKEN', 'INR'), 'not-json{');

      final result = cache.getCachedResult('BROKEN', 'INR');

      expect(result.success, isFalse);
    });
  });

  // The same symbol can be held in two currencies; each price is a number
  // in one of them, so they must never be served for one another.
  group('keyed by symbol and currency', () {
    Future<void> cacheIn(String symbol, double price, String currency) =>
        cache.cachePrice(PriceResult(
          symbol: symbol,
          price: price,
          currency: currency,
          fetchedAt: DateTime.now(),
          success: true,
        ));

    test('one symbol in two currencies keeps both prices', () async {
      await cacheIn('bitcoin', 5800000, 'INR');
      await cacheIn('bitcoin', 70000, 'USD');

      expect(cache.getCachedResult('bitcoin', 'INR').price, 5800000);
      expect(cache.getCachedResult('bitcoin', 'USD').price, 70000);
      expect(cache.getCachedResult('bitcoin', 'EUR').success, isFalse);
    });

    test('the currency code is matched case-insensitively', () async {
      await cacheIn('AAPL', 230, 'USD');

      expect(cache.getCachedResult('AAPL', 'usd').price, 230);
      expect(PriceCacheService.keyFor('AAPL', 'usd'), 'AAPL:USD');
    });

    test('metal entries written before keep their SYMBOL:CURRENCY key',
        () async {
      // Metals were already cached under 'GC=F:INR'.
      await Hive.box(AppConstants.priceCacheBox).put(
        'GC=F:INR',
        '{"price":6500.0,"currency":"INR",'
            '"fetchedAt":"${DateTime.now().toIso8601String()}"}',
      );

      expect(cache.getCachedResult('GC=F', 'INR').price, 6500);
    });

    test('an old bare-symbol entry is no longer read, and does not crash',
        () async {
      // Written before prices were keyed by currency: its number could be
      // in any currency, so it is not served for any of them.
      await Hive.box(AppConstants.priceCacheBox).put(
        'bitcoin',
        '{"price":5800000.0,"currency":"INR",'
            '"fetchedAt":"${DateTime.now().toIso8601String()}"}',
      );

      expect(cache.getCachedResult('bitcoin', 'INR').success, isFalse);
      expect(cache.getCachedResult('bitcoin', 'USD').success, isFalse);
    });

    test('an entry whose stored currency disagrees with its key is ignored',
        () async {
      await Hive.box(AppConstants.priceCacheBox).put(
        'AAPL:INR',
        '{"price":230.0,"currency":"USD",'
            '"fetchedAt":"${DateTime.now().toIso8601String()}"}',
      );
      await Hive.box(AppConstants.priceCacheBox).put('TCS.NS:INR', 42);

      expect(cache.getCachedResult('AAPL', 'INR').success, isFalse);
      expect(cache.getCachedResult('TCS.NS', 'INR').success, isFalse);
    });

    test('a result without a currency is not cached', () async {
      await cacheIn('MYSTERY', 1, '');

      expect(Hive.box(AppConstants.priceCacheBox).isEmpty, isTrue);
    });
  });
}
