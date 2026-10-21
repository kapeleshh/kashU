import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:kashu/core/constants/app_constants.dart';
import 'package:kashu/data/models/asset.dart';
import 'package:kashu/data/models/asset_type.dart';
import 'package:kashu/data/models/transaction.dart';
import 'package:kashu/data/models/transaction_type.dart';
import 'package:kashu/data/repositories/asset_repository.dart';
import 'package:kashu/data/repositories/portfolio_write_service.dart';
import 'package:kashu/data/repositories/transaction_repository.dart';
import 'package:kashu/services/backup_service.dart';
import 'package:kashu/services/export_service.dart';

/// One device's Hive storage, in its own temp directory.
class _Device {
  final Directory dir;
  final AssetRepository assets = AssetRepository();
  final TransactionRepository transactions = TransactionRepository();
  late final PortfolioWriteService writer = PortfolioWriteService(
    assetRepository: assets,
    transactionRepository: transactions,
    settingsBox: Hive.box(AppConstants.settingsBox),
  );

  _Device(this.dir);

  static Future<_Device> open(String name) async {
    final dir = await Directory.systemTemp.createTemp('kashu_backup_$name');
    Hive.init(dir.path);
    await Hive.openBox<Asset>(AppConstants.assetsBox);
    await Hive.openBox<Transaction>(AppConstants.transactionsBox);
    await Hive.openBox(AppConstants.settingsBox);
    return _Device(dir);
  }

  /// The backup file this device's Export Data would write.
  List<int> exportFile() => utf8.encode(BackupService.encode(
        BackupService.buildEnvelope(
          assets: assets.exportToJson(),
          transactions: transactions.exportToJson(),
        ),
      ));

  Set<String> get assetIds => assets.getAllAssets().map((a) => a.id).toSet();

  /// Box contents keyed by id, for order-independent comparison.
  Map<String, dynamic> contents() => {
        'assets': {for (final a in assets.exportToJson()) a['id']: a},
        'transactions': {
          for (final t in transactions.exportToJson()) t['id']: t,
        },
      };

  Future<void> close() async {
    await Hive.close();
    await dir.delete(recursive: true);
  }
}

void main() {
  setUpAll(() {
    Hive.registerAdapter(AssetTypeAdapter());
    Hive.registerAdapter(TransactionTypeAdapter());
    Hive.registerAdapter(AssetAdapter());
    Hive.registerAdapter(TransactionAdapter());
  });

  Future<void> seedPortfolio(_Device device) async {
    // Millisecond precision: that is what Hive keeps on disk.
    final bought = DateTime(2023, 3, 14, 9, 26, 53, 589);
    await device.assets.addAsset(Asset(
      id: 'reliance',
      name: 'Reliance Industries',
      symbol: 'RELIANCE.NS',
      type: AssetType.stock,
      quantity: 12.5,
      purchasePrice: 2400.35,
      currentPrice: 2911.1,
      currency: 'INR',
      purchaseDate: bought,
      platform: 'Zerodha',
      notes: 'Long term — "core" holding',
      createdAt: bought,
      updatedAt: DateTime.utc(2026, 7, 1, 4, 30),
      priceUpdatedAt: DateTime.utc(2026, 7, 1, 4, 30),
    ));
    await device.assets.addAsset(Asset(
      id: 'silver',
      name: 'Silver coins',
      symbol: 'SI=F',
      type: AssetType.gold,
      quantity: 0.000123,
      purchasePrice: 92.4,
      currentPrice: 0,
      currency: 'USD',
      purchaseDate: DateTime(2024, 1, 1),
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    ));
    var n = 0;
    for (final type in TransactionType.values) {
      await device.transactions.addTransaction(Transaction(
        id: 'tx${n++}',
        assetId: 'reliance',
        type: type,
        quantity: 2,
        price: 2500.75,
        amount: 5001.5,
        currency: 'INR',
        date: DateTime(2025, 2, n),
        notes: type == TransactionType.sell ? 'partial exit' : null,
        createdAt: DateTime(2025, 2, n, 10),
      ));
    }
  }

  test('export on one device + import on another restores identical data',
      () async {
    final phoneA = await _Device.open('a');
    await seedPortfolio(phoneA);
    final file = phoneA.exportFile();
    final original = phoneA.contents();
    await phoneA.close();

    final phoneB = await _Device.open('b');
    final backup =
        BackupService.parseBytes(file, existingAssetIds: phoneB.assetIds);
    expect(backup.assets, hasLength(2));
    expect(backup.transactions, hasLength(TransactionType.values.length));
    expect(backup.exportedAt, isNotNull);

    await phoneB.writer
        .importBackup(assets: backup.assets, transactions: backup.transactions);

    expect(phoneB.contents(), original);
    // And the restored data survives a restart of the new phone.
    await Hive.close();
    Hive.init(phoneB.dir.path);
    await Hive.openBox<Asset>(AppConstants.assetsBox);
    await Hive.openBox<Transaction>(AppConstants.transactionsBox);
    await Hive.openBox(AppConstants.settingsBox);
    expect(_Device(phoneB.dir).contents(), original);
    await phoneB.close();
  });

  group('a corrupted file changes nothing', () {
    late _Device phone;
    late Map<String, dynamic> before;
    late List<int> goodFile;

    setUp(() async {
      phone = await _Device.open('c');
      await seedPortfolio(phone);
      goodFile = phone.exportFile();
      before = phone.contents();
    });

    tearDown(() => phone.close());

    /// Parse [file] the way Settings › Import Data does; the import is only
    /// ever written after this succeeds.
    Future<String> importExpectingRejection(List<int> file) async {
      try {
        final backup =
            BackupService.parseBytes(file, existingAssetIds: phone.assetIds);
        await phone.writer.importBackup(
            assets: backup.assets, transactions: backup.transactions);
      } on FormatException catch (e) {
        expect(phone.contents(), before);
        return e.message;
      }
      fail('the corrupted file was accepted');
    }

    test('truncated JSON', () async {
      final message = await importExpectingRejection(
          goodFile.sublist(0, goodFile.length ~/ 2));
      expect(message, contains('not valid JSON'));
      // The decoder's message would quote the file — holdings included.
      expect(message, isNot(contains('Reliance')));
    });

    test('not a text file', () async {
      expect(await importExpectingRejection([0xff, 0xfe, 0x00, 0xd8, 0x00]),
          contains('not a text file'));
    });

    test('one bad record late in an otherwise valid file', () async {
      final json = jsonDecode(utf8.decode(goodFile)) as Map<String, dynamic>;
      final transactions = json['transactions'] as List;
      (transactions.last as Map<String, dynamic>)['type'] = 5;
      // A new asset earlier in the file must not be written either.
      (json['assets'] as List).add({
        ...(json['assets'] as List).first as Map<String, dynamic>,
        'id': 'brand-new',
      });

      final message =
          await importExpectingRejection(utf8.encode(jsonEncode(json)));
      expect(message, contains('"type" must be an integer 0–3'));
      expect(phone.assets.getAssetById('brand-new'), isNull);
    });

    test('an empty backup', () async {
      final empty = utf8.encode(BackupService.encode(
          BackupService.buildEnvelope(assets: [], transactions: [])));
      expect(await importExpectingRejection(empty),
          contains('no assets or transactions'));
    });

    test('a file far too large to be a backup', () async {
      expect(
          await importExpectingRejection(
              List<int>.filled(BackupService.maxBackupBytes + 1, 0x20)),
          contains('too large'));
    });
  });

  test('transactions may belong to an asset already on the device', () async {
    final phone = await _Device.open('d');
    await seedPortfolio(phone);
    final json =
        jsonDecode(utf8.decode(phone.exportFile())) as Map<String, dynamic>;
    (json['assets'] as List).clear();
    (json['transactions'] as List).first['id'] = 'extra-dividend';
    final transactionsOnly = jsonEncode(json);

    final backup =
        BackupService.parse(transactionsOnly, existingAssetIds: phone.assetIds);
    expect(backup.assets, isEmpty);
    expect(backup.transactions, isNotEmpty);
    expect(backup.historyOnlyTransactions, 0);

    // On a device without that asset the same transactions are history.
    final elsewhere =
        BackupService.parse(transactionsOnly, existingAssetIds: const {});
    expect(elsewhere.historyOnlyTransactions, elsewhere.transactions.length);
    await phone.close();
  });

  group('history of holdings deleted earlier', () {
    /// Transactions left behind by the old delete path: their asset is gone.
    Future<void> addOrphanedHistory(_Device device) async {
      for (final (id, type) in [
        ('gone-buy', TransactionType.buy),
        ('gone-sell', TransactionType.sell),
      ]) {
        await device.transactions.addTransaction(Transaction(
          id: id,
          assetId: 'deleted-holding',
          type: type,
          quantity: 4,
          price: 150,
          amount: 600,
          currency: 'INR',
          date: DateTime(2022, 6, type == TransactionType.buy ? 1 : 30),
          createdAt: DateTime(2022, 6, 30),
        ));
      }
    }

    test('an export containing it imports in full and is reported', () async {
      final phoneA = await _Device.open('f');
      await seedPortfolio(phoneA);
      await addOrphanedHistory(phoneA);
      final file = phoneA.exportFile();
      final original = phoneA.contents();
      await phoneA.close();

      final phoneB = await _Device.open('g');
      final backup =
          BackupService.parseBytes(file, existingAssetIds: phoneB.assetIds);
      expect(backup.historyOnlyTransactions, 2);

      await phoneB.writer.importBackup(
          assets: backup.assets, transactions: backup.transactions);
      expect(phoneB.contents(), original);

      // Startup repair never touches unmarked history.
      expect(await phoneB.writer.completeInterruptedWrites(), 0);
      expect(phoneB.contents(), original);
      await phoneB.close();
    });

    test('reports that need a cost basis skip it instead of crashing',
        () async {
      final phone = await _Device.open('h');
      await seedPortfolio(phone);
      final backup = BackupService.parse(
        jsonEncode({
          ...jsonDecode(utf8.decode(phone.exportFile())) as Map,
          'transactions': [
            for (final t in phone.transactions.exportToJson())
              {...t, 'id': 'copy-${t['id']}', 'assetId': 'deleted-holding'},
          ],
        }),
        existingAssetIds: const {},
      );
      await phone.writer.importBackup(
          assets: backup.assets, transactions: backup.transactions);

      final assets = phone.assets.getAllAssets();
      final transactions = phone.transactions.getAllTransactions();
      final names = {for (final a in assets) a.id: a.name};

      // Capital gains: the orphaned sell has no cost basis and is skipped;
      // the original sell of a held asset is still reported.
      final gains =
          ExportService.computeCapitalGains(assets, transactions, names);
      expect(gains, hasLength(1));
      expect(gains.single.assetName, 'Reliance Industries');

      // Activity / CSV list every transaction, falling back to the id.
      final rows = ExportService.transactionsCsvRows(transactions, names);
      expect(rows, hasLength(transactions.length + 1));
      expect(rows.where((r) => r[1] == 'deleted-holding'),
          hasLength(TransactionType.values.length));
      await phone.close();
    });
  });

  test('a leading byte-order mark is tolerated', () async {
    final phone = await _Device.open('e');
    await seedPortfolio(phone);
    final text = '﻿${utf8.decode(phone.exportFile())}';

    final backup = BackupService.parse(text, existingAssetIds: const {});
    expect(backup.assets, hasLength(2));
    await phone.close();
  });
}
