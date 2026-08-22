import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:kashu/core/constants/app_constants.dart';
import 'package:kashu/data/models/asset.dart';
import 'package:kashu/data/models/asset_type.dart';
import 'package:kashu/shared/providers/portfolio_provider.dart';

Asset _makeAsset() {
  final now = DateTime(2024, 1, 1);
  return Asset(
    id: 'a1',
    name: 'Asset',
    type: AssetType.stock,
    quantity: 1,
    purchasePrice: 100,
    currentPrice: 100,
    currency: 'INR',
    purchaseDate: now,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late Directory tempDir;
  late Box settings;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kashu_backup_nudge');
    Hive.init(tempDir.path);
    settings = await Hive.openBox(AppConstants.settingsBox);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  ProviderContainer makeContainer({required bool hasAssets}) {
    final container = ProviderContainer(overrides: [
      allAssetsProvider.overrideWithValue(
          hasAssets ? [_makeAsset()] : const <Asset>[]),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  String iso(Duration ago) =>
      DateTime.now().subtract(ago).toIso8601String();

  test('no assets → never nags', () {
    final container = makeContainer(hasAssets: false);
    expect(container.read(isBackupOverdueProvider), isFalse);
  });

  test('assets but no export ever → overdue', () {
    final container = makeContainer(hasAssets: true);
    expect(container.read(isBackupOverdueProvider), isTrue);
  });

  test('recent export → not overdue', () async {
    await settings.put(
        AppConstants.keyLastExportAt, iso(const Duration(days: 3)));
    final container = makeContainer(hasAssets: true);
    expect(container.read(isBackupOverdueProvider), isFalse);
  });

  test('export older than 30 days → overdue again', () async {
    await settings.put(
        AppConstants.keyLastExportAt, iso(const Duration(days: 45)));
    final container = makeContainer(hasAssets: true);
    expect(container.read(isBackupOverdueProvider), isTrue);
  });

  test('recent dismissal snoozes the nudge', () async {
    await settings.put(AppConstants.keyBackupNudgeDismissedAt,
        iso(const Duration(days: 2)));
    final container = makeContainer(hasAssets: true);
    expect(container.read(isBackupOverdueProvider), isFalse);
  });

  test('dismissal expires after 30 days', () async {
    await settings.put(AppConstants.keyBackupNudgeDismissedAt,
        iso(const Duration(days: 40)));
    final container = makeContainer(hasAssets: true);
    expect(container.read(isBackupOverdueProvider), isTrue);
  });

  test('corrupt timestamps are treated as missing', () async {
    await settings.put(AppConstants.keyLastExportAt, 'not-a-date');
    final container = makeContainer(hasAssets: true);
    expect(container.read(isBackupOverdueProvider), isTrue);
  });
}
