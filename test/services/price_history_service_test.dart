import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:kashu/core/constants/app_constants.dart';
import 'package:kashu/services/price_history_service.dart';

void main() {
  late Directory tempDir;
  late Box box;
  late PriceHistoryService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kashu_history_test');
    Hive.init(tempDir.path);
    box = await Hive.openBox(AppConstants.priceHistoryBox);
    service = PriceHistoryService(box: box);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  DateTime day(int y, int m, int d) => DateTime(y, m, d, 10); // 10am, any time

  group('recordDailySnapshot', () {
    test('stores one entry per day; same day overwrites', () async {
      await service.recordDailySnapshot(
          total: 100, assetValues: {'a': 100}, now: day(2026, 1, 10));
      await service.recordDailySnapshot(
          total: 110, assetValues: {'a': 110}, now: day(2026, 1, 10));
      expect(service.snapshotCount, 1); // same day → one key
    });

    test('different days are separate entries', () async {
      await service.recordDailySnapshot(
          total: 100, assetValues: {'a': 100}, now: day(2026, 1, 10));
      await service.recordDailySnapshot(
          total: 120, assetValues: {'a': 120}, now: day(2026, 1, 11));
      expect(service.snapshotCount, 2);
    });
  });

  group('previousDayTotal', () {
    test('null when only today has a snapshot', () async {
      await service.recordDailySnapshot(
          total: 100, assetValues: {'a': 100}, now: day(2026, 1, 10));
      expect(service.previousDayTotal(now: day(2026, 1, 10)), isNull);
    });

    test('returns the most recent PRIOR day total', () async {
      await service.recordDailySnapshot(
          total: 100, assetValues: {'a': 100}, now: day(2026, 1, 8));
      await service.recordDailySnapshot(
          total: 130, assetValues: {'a': 130}, now: day(2026, 1, 9));
      // "Today" is the 10th → baseline is the 9th (most recent prior).
      expect(service.previousDayTotal(now: day(2026, 1, 10)), 130);
    });

    test('ignores today when a prior day exists', () async {
      await service.recordDailySnapshot(
          total: 100, assetValues: {'a': 100}, now: day(2026, 1, 9));
      await service.recordDailySnapshot(
          total: 999, assetValues: {'a': 999}, now: day(2026, 1, 10));
      expect(service.previousDayTotal(now: day(2026, 1, 10)), 100);
    });
  });

  group('assetSeries', () {
    test('ordered oldest → newest, skips days missing the asset', () async {
      await service.recordDailySnapshot(
          total: 100, assetValues: {'a': 10, 'b': 5}, now: day(2026, 1, 8));
      await service.recordDailySnapshot(
          total: 120, assetValues: {'b': 6}, now: day(2026, 1, 9)); // no 'a'
      await service.recordDailySnapshot(
          total: 140, assetValues: {'a': 12, 'b': 7}, now: day(2026, 1, 10));

      expect(service.assetSeries('a'), [10, 12]); // day 9 skipped
      expect(service.assetSeries('b'), [5, 6, 7]);
      expect(service.assetSeries('missing'), isEmpty);
    });
  });

  group('retention / prune', () {
    test('drops snapshots older than 90 days on record', () async {
      final now = day(2026, 4, 15);
      // 100 days ago — should be pruned when we record today.
      await service.recordDailySnapshot(
          total: 50, assetValues: {'a': 50}, now: now.subtract(const Duration(days: 100)));
      // 10 days ago — should survive.
      await service.recordDailySnapshot(
          total: 80, assetValues: {'a': 80}, now: now.subtract(const Duration(days: 10)));
      await service.recordDailySnapshot(
          total: 90, assetValues: {'a': 90}, now: now);

      expect(service.snapshotCount, 2); // the 100-day-old one was pruned
      expect(service.assetSeries('a'), [80, 90]);
    });
  });

  test('corrupt entries are ignored, not thrown on', () async {
    await box.put('garbage', 'not-json{');
    await service.recordDailySnapshot(
        total: 100, assetValues: {'a': 100}, now: day(2026, 1, 10));
    expect(service.assetSeries('a'), [100]);
    expect(service.previousDayTotal(now: day(2026, 1, 11)), 100);
  });
}
