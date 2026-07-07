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

      final result = cache.getCachedResult('AAPL');

      expect(result.success, isTrue);
      expect(result.price, 200.0);
      expect(result.isStale, isFalse);
    });

    test('entry older than the TTL but within 7 days is served as stale, '
        'keeping its original fetch time', () async {
      final fetchedAt = DateTime.now().subtract(const Duration(days: 2));
      await cacheAt('AAPL', 195.0, fetchedAt);

      final result = cache.getCachedResult('AAPL');

      expect(result.success, isTrue);
      expect(result.price, 195.0);
      expect(result.isStale, isTrue);
      expect(result.fetchedAt.difference(fetchedAt).inSeconds.abs(),
          lessThan(2));
    });

    test('entry older than 7 days is treated as missing', () async {
      final fetchedAt = DateTime.now().subtract(const Duration(days: 8));
      await cacheAt('AAPL', 180.0, fetchedAt);

      final result = cache.getCachedResult('AAPL');

      expect(result.success, isFalse);
      expect(result.error, contains('older than'));
    });

    test('a custom maxAge bound is respected', () async {
      final fetchedAt = DateTime.now().subtract(const Duration(hours: 3));
      await cacheAt('AAPL', 190.0, fetchedAt);

      expect(
        cache
            .getCachedResult('AAPL', maxAge: const Duration(hours: 1))
            .success,
        isFalse,
      );
      expect(
        cache
            .getCachedResult('AAPL', maxAge: const Duration(hours: 6))
            .success,
        isTrue,
      );
    });

    test('missing symbol returns a failure', () {
      final result = cache.getCachedResult('UNKNOWN');
      expect(result.success, isFalse);
      expect(result.error, contains('No cached price'));
    });

    test('corrupt entry returns a failure instead of throwing', () async {
      await Hive.box(AppConstants.priceCacheBox).put('BROKEN', 'not-json{');

      final result = cache.getCachedResult('BROKEN');

      expect(result.success, isFalse);
    });
  });
}
