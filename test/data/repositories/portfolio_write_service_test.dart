import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';

import 'package:kashu/core/constants/app_constants.dart';
import 'package:kashu/data/models/asset.dart';
import 'package:kashu/data/models/asset_type.dart';
import 'package:kashu/data/models/transaction.dart';
import 'package:kashu/data/models/transaction_type.dart';
import 'package:kashu/data/repositories/asset_repository.dart';
import 'package:kashu/data/repositories/portfolio_write_service.dart';
import 'package:kashu/data/repositories/transaction_repository.dart';

class MockAssetRepository extends Mock implements AssetRepository {}

class MockTransactionRepository extends Mock
    implements TransactionRepository {}

Asset makeAsset({String id = 'a1'}) {
  final now = DateTime(2024, 1, 15);
  return Asset(
    id: id,
    name: 'Asset $id',
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

Transaction makeTransaction({String id = 't1', required String assetId}) {
  final now = DateTime(2024, 1, 15);
  return Transaction(
    id: id,
    assetId: assetId,
    type: TransactionType.buy,
    quantity: 1,
    price: 100,
    amount: 100,
    currency: 'INR',
    date: now,
    createdAt: now,
  );
}

void main() {
  late Directory tempDir;
  late Box settings;

  setUpAll(() {
    registerFallbackValue(makeAsset());
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kashu_write_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(AssetTypeAdapter().typeId)) {
      Hive.registerAdapter(AssetTypeAdapter());
      Hive.registerAdapter(TransactionTypeAdapter());
      Hive.registerAdapter(AssetAdapter());
      Hive.registerAdapter(TransactionAdapter());
    }
    await Hive.openBox<Asset>(AppConstants.assetsBox);
    await Hive.openBox<Transaction>(AppConstants.transactionsBox);
    settings = await Hive.openBox(AppConstants.settingsBox);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  List<String> pendingDeletes() {
    final raw = settings.get(AppConstants.keyPendingAssetDeletes);
    return raw is List ? raw.whereType<String>().toList() : <String>[];
  }

  group('addAssetWithBuyTransaction', () {
    late MockAssetRepository assetRepo;
    late MockTransactionRepository txRepo;
    late PortfolioWriteService service;

    setUp(() {
      assetRepo = MockAssetRepository();
      txRepo = MockTransactionRepository();
      service = PortfolioWriteService(
        assetRepository: assetRepo,
        transactionRepository: txRepo,
        settingsBox: settings,
      );
    });

    test('adds the asset and logs its buy transaction', () async {
      final asset = makeAsset();
      when(() => assetRepo.addAsset(asset)).thenAnswer((_) async {});
      when(() => txRepo.logBuyTransaction(asset)).thenAnswer((_) async {});

      await service.addAssetWithBuyTransaction(asset);

      verify(() => assetRepo.addAsset(asset)).called(1);
      verify(() => txRepo.logBuyTransaction(asset)).called(1);
      verifyNever(() => assetRepo.deleteAsset(any()));
    });

    test('compensates by deleting the asset when logging throws', () async {
      final asset = makeAsset();
      when(() => assetRepo.addAsset(asset)).thenAnswer((_) async {});
      when(() => txRepo.logBuyTransaction(asset))
          .thenThrow(HiveError('disk full'));
      when(() => assetRepo.deleteAsset(asset.id)).thenAnswer((_) async {});

      await expectLater(
        () => service.addAssetWithBuyTransaction(asset),
        throwsA(isA<HiveError>()),
      );

      verify(() => assetRepo.deleteAsset(asset.id)).called(1);
    });
  });

  group('deleteAssetWithTransactions', () {
    test('deletes the asset and its transactions and clears the tombstone',
        () async {
      final assetRepo = AssetRepository();
      final txRepo = TransactionRepository();
      final service = PortfolioWriteService(
        assetRepository: assetRepo,
        transactionRepository: txRepo,
        settingsBox: settings,
      );

      await assetRepo.addAsset(makeAsset(id: 'a1'));
      await txRepo.addTransaction(makeTransaction(id: 't1', assetId: 'a1'));

      await service.deleteAssetWithTransactions('a1');

      expect(assetRepo.getAssetById('a1'), isNull);
      expect(txRepo.getAllTransactions(), isEmpty);
      expect(pendingDeletes(), isEmpty);
    });

    test('keeps the tombstone when transaction cleanup fails', () async {
      final assetRepo = MockAssetRepository();
      final txRepo = MockTransactionRepository();
      final service = PortfolioWriteService(
        assetRepository: assetRepo,
        transactionRepository: txRepo,
        settingsBox: settings,
      );

      when(() => assetRepo.deleteAsset('a1')).thenAnswer((_) async {});
      when(() => txRepo.deleteTransactionsForAsset('a1'))
          .thenThrow(HiveError('boom'));

      await expectLater(service.deleteAssetWithTransactions('a1'), completes);

      verify(() => assetRepo.deleteAsset('a1')).called(1);
      expect(pendingDeletes(), ['a1']);
    });
  });

  group('completeInterruptedDeletes', () {
    late AssetRepository assetRepo;
    late TransactionRepository txRepo;
    late PortfolioWriteService service;

    setUp(() {
      assetRepo = AssetRepository();
      txRepo = TransactionRepository();
      service = PortfolioWriteService(
        assetRepository: assetRepo,
        transactionRepository: txRepo,
        settingsBox: settings,
      );
    });

    test('finishes a tombstoned delete and clears the tombstone', () async {
      // Crash happened after the asset was deleted but before its
      // transactions were: tombstone present, orphans remain.
      await settings.put(AppConstants.keyPendingAssetDeletes, ['gone']);
      await txRepo.addTransaction(makeTransaction(id: 't1', assetId: 'gone'));
      await txRepo.addTransaction(makeTransaction(id: 't2', assetId: 'gone'));

      final removed = await service.completeInterruptedDeletes();

      expect(removed, 2);
      expect(txRepo.getAllTransactions(), isEmpty);
      expect(pendingDeletes(), isEmpty);
    });

    test('also removes the asset when the crash preceded its delete',
        () async {
      await settings.put(AppConstants.keyPendingAssetDeletes, ['a1']);
      await assetRepo.addAsset(makeAsset(id: 'a1'));
      await txRepo.addTransaction(makeTransaction(id: 't1', assetId: 'a1'));

      await service.completeInterruptedDeletes();

      expect(assetRepo.getAssetById('a1'), isNull);
      expect(txRepo.getAllTransactions(), isEmpty);
      expect(pendingDeletes(), isEmpty);
    });

    test('never touches orphans without a tombstone — they are user history',
        () async {
      // Orphans from the pre-tombstone delete path or from an imported
      // backup: they feed the Activity screen and tax exports, and used to
      // be silently destroyed by the old startup sweep.
      await txRepo
          .addTransaction(makeTransaction(id: 'legacy', assetId: 'old-asset'));
      await txRepo.addTransaction(
          makeTransaction(id: 'imported', assetId: 'not-in-backup'));

      final removed = await service.completeInterruptedDeletes();

      expect(removed, 0);
      expect(txRepo.getAllTransactions(), hasLength(2));
    });

    test('is a no-op when there are no tombstones', () async {
      await assetRepo.addAsset(makeAsset(id: 'live'));
      await txRepo.addTransaction(makeTransaction(id: 't1', assetId: 'live'));

      expect(await service.completeInterruptedDeletes(), 0);
      expect(txRepo.getAllTransactions(), hasLength(1));
    });

    test('failed cleanup is completed on the next launch', () async {
      // Launch 1: transaction cleanup throws mid-delete.
      final throwingTx = MockTransactionRepository();
      when(() => throwingTx.deleteTransactionsForAsset('a1'))
          .thenThrow(HiveError('interrupted'));
      final crashingService = PortfolioWriteService(
        assetRepository: assetRepo,
        transactionRepository: throwingTx,
        settingsBox: settings,
      );
      await assetRepo.addAsset(makeAsset(id: 'a1'));
      await txRepo.addTransaction(makeTransaction(id: 't1', assetId: 'a1'));
      await crashingService.deleteAssetWithTransactions('a1');
      expect(pendingDeletes(), ['a1']);
      expect(txRepo.getAllTransactions(), hasLength(1)); // orphan left

      // Launch 2: startup completion finishes the job.
      final removed = await service.completeInterruptedDeletes();

      expect(removed, 1);
      expect(txRepo.getAllTransactions(), isEmpty);
      expect(pendingDeletes(), isEmpty);
    });
  });
}
