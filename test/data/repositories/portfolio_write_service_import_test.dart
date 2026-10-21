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

Asset makeAsset(String id, {double quantity = 1, String? notes}) {
  final when = DateTime(2024, 1, 15);
  return Asset(
    id: id,
    name: 'Asset $id',
    type: AssetType.stock,
    quantity: quantity,
    purchasePrice: 100,
    currentPrice: 120,
    currency: 'INR',
    purchaseDate: when,
    notes: notes,
    createdAt: when,
    updatedAt: when,
  );
}

Transaction makeTransaction(String id, String assetId, {double amount = 100}) {
  final when = DateTime(2024, 1, 15);
  return Transaction(
    id: id,
    assetId: assetId,
    type: TransactionType.buy,
    quantity: 1,
    price: amount,
    amount: amount,
    currency: 'INR',
    date: when,
    createdAt: when,
  );
}

/// Real Hive-backed repository whose Nth [addTransaction] throws — a disk
/// that fills up half-way through an import.
class FailingTransactionRepository extends TransactionRepository {
  final int failOnCall;
  int _calls = 0;
  FailingTransactionRepository({required this.failOnCall});

  @override
  Future<void> addTransaction(Transaction transaction) async {
    _calls++;
    if (_calls == failOnCall) throw HiveError('disk full');
    await super.addTransaction(transaction);
  }
}

void main() {
  late Directory tempDir;
  late Box settings;
  late AssetRepository assetRepo;
  late TransactionRepository txRepo;

  Future<void> openBoxes() async {
    await Hive.openBox<Asset>(AppConstants.assetsBox);
    await Hive.openBox<Transaction>(AppConstants.transactionsBox);
    settings = await Hive.openBox(AppConstants.settingsBox);
    assetRepo = AssetRepository();
    txRepo = TransactionRepository();
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kashu_import_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(AssetTypeAdapter().typeId)) {
      Hive.registerAdapter(AssetTypeAdapter());
      Hive.registerAdapter(TransactionTypeAdapter());
      Hive.registerAdapter(AssetAdapter());
      Hive.registerAdapter(TransactionAdapter());
    }
    await openBoxes();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  PortfolioWriteService serviceWith({TransactionRepository? transactions}) =>
      PortfolioWriteService(
        assetRepository: assetRepo,
        transactionRepository: transactions ?? txRepo,
        settingsBox: settings,
      );

  /// Everything the import could touch, as plain JSON for comparisons.
  Map<String, dynamic> snapshot() => {
        'assets': {
          for (final a in assetRepo.getAllAssets()) a.id: a.toJson(),
        },
        'transactions': {
          for (final t in txRepo.getAllTransactions()) t.id: t.toJson(),
        },
        'pendingDeletes':
            settings.get(AppConstants.keyPendingAssetDeletes) ?? const [],
      };

  /// Existing device data the import overlaps with: a1 and t0 are replaced
  /// by the backup's versions, and (by default) a tombstone for a1 is
  /// pending.
  Future<void> seedDevice(
      {List<String> tombstones = const ['a1', 'other']}) async {
    await assetRepo.addAsset(makeAsset('a1', quantity: 5, notes: 'on device'));
    await txRepo.addTransaction(makeTransaction('t0', 'a1', amount: 500));
    await settings.put(AppConstants.keyPendingAssetDeletes, tombstones);
  }

  // Built per call, not shared: a HiveObject instance can only ever live in
  // one box, and every test opens fresh boxes.
  List<Asset> backupAssets() => [makeAsset('a1', quantity: 9), makeAsset('a2')];
  List<Transaction> backupTransactions() => [
        makeTransaction('t0', 'a1', amount: 900),
        makeTransaction('t1', 'a2'),
        makeTransaction('t2', 'a2'),
      ];

  test('adds new records, replaces same-id ones and drops their tombstones',
      () async {
    await seedDevice();

    await serviceWith().importBackup(
        assets: backupAssets(), transactions: backupTransactions());

    expect(assetRepo.getAssetById('a1')!.quantity, 9);
    expect(assetRepo.getAssetById('a2'), isNotNull);
    expect(txRepo.getAllTransactions().map((t) => t.id),
        unorderedEquals(['t0', 't1', 't2']));
    expect(txRepo.getAllTransactions().firstWhere((t) => t.id == 't0').amount,
        900);
    expect(settings.get(AppConstants.keyPendingAssetDeletes), ['other']);
    expect(settings.get(AppConstants.keyPendingImport), isNull);
  });

  test('a failure half-way through leaves both boxes exactly as they were',
      () async {
    await seedDevice();
    final before = snapshot();

    // Assets and the first transaction are written, then the disk "fills".
    final service =
        serviceWith(transactions: FailingTransactionRepository(failOnCall: 2));
    await expectLater(
      service.importBackup(
          assets: backupAssets(), transactions: backupTransactions()),
      throwsA(isA<HiveError>()),
    );

    expect(snapshot(), before);
    expect(assetRepo.getAssetById('a1')!.notes, 'on device');
    expect(assetRepo.getAssetById('a2'), isNull);
    expect(settings.get(AppConstants.keyPendingImport), isNull);
  });

  test('an import the app died during is rolled back at the next launch',
      () async {
    // No tombstones here: startup would (rightly) go on to finish a pending
    // delete after the rollback, which is not what this test is about.
    await seedDevice(tombstones: const []);
    final before = snapshot();

    // Launch 1: the rollback itself can't run either (every write after
    // the first transaction fails), so the journal is all that's left.
    final dying = PortfolioWriteService(
      assetRepository: assetRepo,
      transactionRepository: _AlwaysFailingAfter(1),
      settingsBox: settings,
    );
    await expectLater(
      dying.importBackup(
          assets: backupAssets(), transactions: backupTransactions()),
      throwsA(isA<HiveError>()),
    );
    expect(settings.get(AppConstants.keyPendingImport), isNotNull);

    // Restart: the journal round-trips through Hive as Map<dynamic, dynamic>.
    await Hive.close();
    await openBoxes();
    expect(assetRepo.getAssetById('a2'), isNotNull,
        reason: 'half-written import visible before the rollback');

    await serviceWith().completeInterruptedWrites();

    expect(snapshot(), before);
    expect(settings.get(AppConstants.keyPendingImport), isNull);
  });

  test('a completed import leaves no journal for startup to undo', () async {
    await serviceWith().importBackup(
        assets: backupAssets(), transactions: backupTransactions());
    final after = snapshot();

    await serviceWith().completeInterruptedWrites();

    expect(snapshot(), after);
  });

  group('history of holdings deleted earlier (no matching asset)', () {
    test('a failed import rolls it back like any other record', () async {
      // The device already holds history for a deleted holding.
      await txRepo.addTransaction(makeTransaction('h1', 'deleted', amount: 10));
      final before = snapshot();

      final service = serviceWith(
          transactions: FailingTransactionRepository(failOnCall: 2));
      await expectLater(
        service.importBackup(assets: const [], transactions: [
          makeTransaction('h1', 'deleted', amount: 99), // replaces h1
          makeTransaction('h2', 'deleted'), // fails
        ]),
        throwsA(isA<HiveError>()),
      );

      expect(snapshot(), before);
    });

    test('an interrupted import of it is rolled back at the next launch',
        () async {
      await txRepo.addTransaction(makeTransaction('h1', 'deleted', amount: 10));
      final before = snapshot();

      final dying = PortfolioWriteService(
        assetRepository: assetRepo,
        transactionRepository: _AlwaysFailingAfter(1),
        settingsBox: settings,
      );
      await expectLater(
        dying.importBackup(assets: const [], transactions: [
          makeTransaction('h1', 'deleted', amount: 99),
          makeTransaction('h2', 'deleted'),
        ]),
        throwsA(isA<HiveError>()),
      );

      await Hive.close();
      await openBoxes();
      await serviceWith().completeInterruptedWrites();

      expect(snapshot(), before);
    });

    test(
        'importing it drops the delete tombstone of its holding, so startup '
        "can't delete what was just restored", () async {
      await settings.put(AppConstants.keyPendingAssetDeletes, ['deleted']);

      await serviceWith().importBackup(assets: const [], transactions: [
        makeTransaction('h1', 'deleted'),
        makeTransaction('h2', 'deleted'),
      ]);
      expect(settings.get(AppConstants.keyPendingAssetDeletes), isEmpty);

      expect(await serviceWith().completeInterruptedWrites(), 0);
      expect(txRepo.getAllTransactions().map((t) => t.id),
          unorderedEquals(['h1', 'h2']));
    });
  });
}

/// Lets the first [okCalls] transaction writes through, then fails every
/// write — including the ones a rollback would need.
class _AlwaysFailingAfter extends TransactionRepository {
  final int okCalls;
  int _calls = 0;
  _AlwaysFailingAfter(this.okCalls);

  @override
  Future<void> addTransaction(Transaction transaction) async {
    if (++_calls > okCalls) throw HiveError('disk full');
    await super.addTransaction(transaction);
  }

  @override
  Future<void> deleteTransaction(String id) async =>
      throw HiveError('disk full');
}
