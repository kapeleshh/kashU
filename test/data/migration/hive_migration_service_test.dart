import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:kashu/core/constants/app_constants.dart';
import 'package:kashu/data/migration/hive_migration_service.dart';
import 'package:kashu/data/models/asset.dart';
import 'package:kashu/data/models/asset_type.dart';

/// The Asset adapter as generated for schema v1 (fields 0–13), so the test
/// writes exactly the bytes an installed v1 app left on disk.
class _V1AssetAdapter extends TypeAdapter<Asset> {
  @override
  final int typeId = 2;

  @override
  Asset read(BinaryReader reader) => throw UnimplementedError('write-only');

  @override
  void write(BinaryWriter writer, Asset obj) {
    writer
      ..writeByte(14)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.symbol)
      ..writeByte(3)
      ..write(obj.type)
      ..writeByte(4)
      ..write(obj.quantity)
      ..writeByte(5)
      ..write(obj.purchasePrice)
      ..writeByte(6)
      ..write(obj.currentPrice)
      ..writeByte(7)
      ..write(obj.currency)
      ..writeByte(8)
      ..write(obj.purchaseDate)
      ..writeByte(9)
      ..write(obj.platform)
      ..writeByte(10)
      ..write(obj.notes)
      ..writeByte(11)
      ..write(obj.createdAt)
      ..writeByte(12)
      ..write(obj.updatedAt)
      ..writeByte(13)
      ..write(obj.priceUpdatedAt);
  }
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kashu_migration');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  test('a v1 deposit survives the v2 migration untouched', () async {
    final opened = DateTime(2023, 4, 1);
    final v1Deposit = Asset(
      id: 'sbi-fd',
      name: 'SBI FD',
      type: AssetType.fixedDeposit,
      quantity: 1,
      purchasePrice: 100000,
      currentPrice: 104250.5,
      currency: 'INR',
      purchaseDate: opened,
      platform: 'Bank FD',
      notes: 'renews in April',
      createdAt: opened,
      updatedAt: DateTime(2025, 1, 2),
      priceUpdatedAt: DateTime(2025, 1, 2),
    );

    // An installed v1 app: v1 records, schema version 1 in settings.
    Hive.registerAdapter(AssetTypeAdapter());
    Hive.registerAdapter<Asset>(_V1AssetAdapter());
    final v1Box = await Hive.openBox<Asset>(AppConstants.assetsBox);
    await v1Box.put(v1Deposit.id, v1Deposit);
    final v1Settings = await Hive.openBox(AppConstants.settingsBox);
    await v1Settings.put(AppConstants.keySchemaVersion, 1);
    await Hive.close();

    // The update: today's adapter reads the same files.
    Hive.registerAdapter<Asset>(AssetAdapter(), override: true);
    final assets = await Hive.openBox<Asset>(AppConstants.assetsBox);
    final settings = await Hive.openBox(AppConstants.settingsBox);

    await HiveMigrationService.runMigrations();

    expect(settings.get(AppConstants.keySchemaVersion), 2);
    final migrated = assets.get('sbi-fd')!;
    expect(migrated.toJson()..removeWhere((k, _) => k.startsWith('deposit')),
        {...v1Deposit.toJson()}..removeWhere((k, _) => k.startsWith('deposit')));
    expect(migrated.depositRatePercent, isNull);
    expect(migrated.depositMaturityDate, isNull);
    expect(migrated.depositCompounding, isNull);
    expect(migrated.rdMonthlyInstalment, isNull);
    // Still valued by hand, exactly as before the update.
    expect(migrated.hasDepositSchedule, isFalse);
    expect(migrated.currentValue, 104250.5);
    expect(migrated.totalInvested, 100000);

    // Running again (next launch) is a no-op.
    await HiveMigrationService.runMigrations();
    expect(settings.get(AppConstants.keySchemaVersion), 2);
    expect(assets.get('sbi-fd')!.currentValue, 104250.5);
  });

  test('a fresh install lands on the current schema version', () async {
    final settings = await Hive.openBox(AppConstants.settingsBox);

    await HiveMigrationService.runMigrations();

    expect(settings.get(AppConstants.keySchemaVersion), 2);
  });
}
