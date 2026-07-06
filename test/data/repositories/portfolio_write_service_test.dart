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
  setUpAll(() {
    registerFallbackValue(makeAsset());
  });

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
    late MockAssetRepository assetRepo;
    late MockTransactionRepository txRepo;
    late PortfolioWriteService service;

    setUp(() {
      assetRepo = MockAssetRepository();
      txRepo = MockTransactionRepository();
      service = PortfolioWriteService(
        assetRepository: assetRepo,
        transactionRepository: txRepo,
      );
    });

    test('deletes the asset and its transactions', () async {
      when(() => assetRepo.deleteAsset('a1')).thenAnswer((_) async {});
      when(() => txRepo.deleteTransactionsForAsset('a1'))
          .thenAnswer((_) async {});

      await service.deleteAssetWithTransactions('a1');

      verify(() => assetRepo.deleteAsset('a1')).called(1);
      verify(() => txRepo.deleteTransactionsForAsset('a1')).called(1);
    });

    test('swallows transaction-cleanup failures (sweep handles them)',
        () async {
      when(() => assetRepo.deleteAsset('a1')).thenAnswer((_) async {});
      when(() => txRepo.deleteTransactionsForAsset('a1'))
          .thenThrow(HiveError('boom'));

      await expectLater(
          service.deleteAssetWithTransactions('a1'), completes);

      verify(() => assetRepo.deleteAsset('a1')).called(1);
    });
  });

  group('sweepOrphanedTransactions (real Hive)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('kashu_sweep_test');
      Hive.init(tempDir.path);
      if (!Hive.isAdapterRegistered(AssetTypeAdapter().typeId)) {
        Hive.registerAdapter(AssetTypeAdapter());
        Hive.registerAdapter(TransactionTypeAdapter());
        Hive.registerAdapter(AssetAdapter());
        Hive.registerAdapter(TransactionAdapter());
      }
      await Hive.openBox<Asset>(AppConstants.assetsBox);
      await Hive.openBox<Transaction>(AppConstants.transactionsBox);
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await tempDir.delete(recursive: true);
    });

    test('removes transactions whose asset is gone, keeps the rest',
        () async {
      final assetRepo = AssetRepository();
      final txRepo = TransactionRepository();
      final service = PortfolioWriteService(
        assetRepository: assetRepo,
        transactionRepository: txRepo,
      );

      final live = makeAsset(id: 'live');
      await assetRepo.addAsset(live);
      await txRepo.addTransaction(makeTransaction(id: 't1', assetId: 'live'));
      await txRepo
          .addTransaction(makeTransaction(id: 't2', assetId: 'deleted'));
      await txRepo
          .addTransaction(makeTransaction(id: 't3', assetId: 'deleted'));

      final removed = await service.sweepOrphanedTransactions();

      expect(removed, 2);
      final remaining = txRepo.getAllTransactions();
      expect(remaining, hasLength(1));
      expect(remaining.single.id, 't1');
    });

    test('is a no-op when nothing is orphaned', () async {
      final assetRepo = AssetRepository();
      final txRepo = TransactionRepository();
      final service = PortfolioWriteService(
        assetRepository: assetRepo,
        transactionRepository: txRepo,
      );

      await assetRepo.addAsset(makeAsset(id: 'live'));
      await txRepo.addTransaction(makeTransaction(id: 't1', assetId: 'live'));

      expect(await service.sweepOrphanedTransactions(), 0);
      expect(txRepo.getAllTransactions(), hasLength(1));
    });
  });
}
