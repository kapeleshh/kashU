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

/// A box whose clear fails, as on a full disk.
class _ThrowingBox extends Mock implements Box<dynamic> {
  @override
  Future<int> clear() async => throw HiveError('disk full');
}

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

    test(
        'removes the tombstone and rethrows when the asset delete itself '
        'fails — a visible failed delete, not a deferred surprise one',
        () async {
      final assetRepo = MockAssetRepository();
      final txRepo = MockTransactionRepository();
      final service = PortfolioWriteService(
        assetRepository: assetRepo,
        transactionRepository: txRepo,
        settingsBox: settings,
      );

      when(() => assetRepo.deleteAsset('a1')).thenThrow(HiveError('locked'));

      await expectLater(
        () => service.deleteAssetWithTransactions('a1'),
        throwsA(isA<HiveError>()),
      );

      verifyNever(() => txRepo.deleteTransactionsForAsset(any()));
      expect(pendingDeletes(), isEmpty);
    });
  });

  group('completeInterruptedWrites', () {
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

      final removed = await service.completeInterruptedWrites();

      expect(removed, 2);
      expect(txRepo.getAllTransactions(), isEmpty);
      expect(pendingDeletes(), isEmpty);
    });

    test('also removes the asset when the crash preceded its delete',
        () async {
      await settings.put(AppConstants.keyPendingAssetDeletes, ['a1']);
      await assetRepo.addAsset(makeAsset(id: 'a1'));
      await txRepo.addTransaction(makeTransaction(id: 't1', assetId: 'a1'));

      await service.completeInterruptedWrites();

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

      final removed = await service.completeInterruptedWrites();

      expect(removed, 0);
      expect(txRepo.getAllTransactions(), hasLength(2));
    });

    test('is a no-op when there are no tombstones', () async {
      await assetRepo.addAsset(makeAsset(id: 'live'));
      await txRepo.addTransaction(makeTransaction(id: 't1', assetId: 'live'));

      expect(await service.completeInterruptedWrites(), 0);
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
      final removed = await service.completeInterruptedWrites();

      expect(removed, 1);
      expect(txRepo.getAllTransactions(), isEmpty);
      expect(pendingDeletes(), isEmpty);
    });

    test('handles a pending list that round-trips as List<dynamic>',
        () async {
      // After a real restart Hive returns List<dynamic>; non-string junk
      // from a corrupted value must be ignored, not thrown on.
      await settings.put(
          AppConstants.keyPendingAssetDeletes, <dynamic>['gone', 42, null]);
      await txRepo.addTransaction(makeTransaction(id: 't1', assetId: 'gone'));

      final removed = await service.completeInterruptedWrites();

      expect(removed, 1);
      expect(txRepo.getAllTransactions(), isEmpty);
      expect(pendingDeletes(), isEmpty);
    });

    test('an import that restores a tombstoned asset id wins over the '
        'tombstone', () async {
      // Interrupted delete left a tombstone for a1...
      await settings.put(AppConstants.keyPendingAssetDeletes, ['a1']);
      // ...then the user restored a backup containing a1 (the import flow
      // calls removeTombstonesFor with the imported asset ids).
      await assetRepo.addAsset(makeAsset(id: 'a1'));
      await txRepo.addTransaction(makeTransaction(id: 't1', assetId: 'a1'));
      await service.removeTombstonesFor(['a1', 'other']);

      final removed = await service.completeInterruptedWrites();

      expect(removed, 0);
      expect(assetRepo.getAssetById('a1'), isNotNull);
      expect(txRepo.getAllTransactions(), hasLength(1));
      expect(pendingDeletes(), isEmpty);
    });
  });

  group('clearAllData', () {
    late AssetRepository assetRepo;
    late TransactionRepository txRepo;
    late Box history;
    late Box priceCache;
    late int widgetClears;
    late PortfolioWriteService service;

    setUp(() async {
      assetRepo = AssetRepository();
      txRepo = TransactionRepository();
      history = await Hive.openBox(AppConstants.priceHistoryBox);
      priceCache = await Hive.openBox(AppConstants.priceCacheBox);
      widgetClears = 0;
      service = PortfolioWriteService(
        assetRepository: assetRepo,
        transactionRepository: txRepo,
        settingsBox: settings,
        priceHistoryBox: history,
        priceCacheBox: priceCache,
        clearHomeWidget: () async => widgetClears++,
      );
    });

    /// A portfolio with something in every place Clear All must reach,
    /// next to the user's preferences.
    Future<void> seedEverything() async {
      await assetRepo.addAsset(makeAsset(id: 'a1'));
      await txRepo.addTransaction(makeTransaction(id: 't1', assetId: 'a1'));
      await history.put('2026-10-21', '{"total":1000}');
      await priceCache.put('RELIANCE.NS:INR', '{"price":2450}');
      await settings.putAll({
        // portfolio data
        'rebal_stock': 60.0,
        'rebal_crypto': 40.0,
        AppConstants.keyPendingAssetDeletes: ['stale'],
        AppConstants.keyPendingImport: {'assets': {}},
        AppConstants.keyLastExportAt: '2026-10-01T00:00:00.000',
        AppConstants.keyBackupNudgeDismissedAt: '2026-10-02T00:00:00.000',
        'lastPriceRefreshAt': '2026-10-21T09:00:00.000',
        // preferences
        AppConstants.keyBaseCurrency: 'USD',
        AppConstants.keyThemeMode: 'dark',
        AppConstants.keyOnboardingComplete: true,
        AppConstants.keyAppLockEnabled: true,
        AppConstants.keyCrashReportingEnabled: true,
        AppConstants.keySchemaVersion: 1,
      });
    }

    test('clears both boxes, all tombstones, and the pending-clear flag',
        () async {
      await assetRepo.addAsset(makeAsset(id: 'a1'));
      await txRepo.addTransaction(makeTransaction(id: 't1', assetId: 'a1'));
      await settings.put(AppConstants.keyPendingAssetDeletes, ['stale']);

      await service.clearAllData();

      expect(assetRepo.getAllAssets(), isEmpty);
      expect(txRepo.getAllTransactions(), isEmpty);
      expect(pendingDeletes(), isEmpty);
      expect(settings.get(AppConstants.keyPendingClearAll), isFalse);
    });

    test(
        'erases price history, price cache, rebalancing targets, markers '
        'and the widget — and keeps every preference', () async {
      await seedEverything();

      await service.clearAllData();

      expect(history.isEmpty, isTrue);
      expect(priceCache.isEmpty, isTrue);
      expect(widgetClears, 1);
      expect(
        Map.of(settings.toMap())..remove(AppConstants.keyPendingClearAll),
        {
          AppConstants.keyBaseCurrency: 'USD',
          AppConstants.keyThemeMode: 'dark',
          AppConstants.keyOnboardingComplete: true,
          AppConstants.keyAppLockEnabled: true,
          AppConstants.keyCrashReportingEnabled: true,
          AppConstants.keySchemaVersion: 1,
        },
      );
    });

    test('a widget that cannot be blanked does not fail the clear', () async {
      await seedEverything();
      final noWidget = PortfolioWriteService(
        assetRepository: assetRepo,
        transactionRepository: txRepo,
        settingsBox: settings,
        priceHistoryBox: history,
        priceCacheBox: priceCache,
        clearHomeWidget: () async => throw Exception('MissingPlugin'),
      );

      await noWidget.clearAllData();

      expect(assetRepo.getAllAssets(), isEmpty);
      expect(history.isEmpty, isTrue);
      expect(settings.get(AppConstants.keyPendingClearAll), isFalse);
    });

    test('a failure leaves the flag set, so the next launch finishes it',
        () async {
      await seedEverything();
      final failing = PortfolioWriteService(
        assetRepository: assetRepo,
        transactionRepository: txRepo,
        settingsBox: settings,
        priceHistoryBox: history,
        priceCacheBox: _ThrowingBox(),
        clearHomeWidget: () async => widgetClears++,
      );

      await expectLater(failing.clearAllData, throwsA(isA<HiveError>()));
      expect(settings.get(AppConstants.keyPendingClearAll), isTrue);

      await service.completeInterruptedWrites();

      expect(priceCache.isEmpty, isTrue);
      expect(settings.get('rebal_stock'), isNull);
      expect(widgetClears, 1);
      expect(settings.get(AppConstants.keyPendingClearAll), isFalse);
    });

    test('an interrupted clear-all is finished at the next launch', () async {
      // Crash happened after the flag was set but before the boxes were
      // fully cleared: assets box already empty, transactions left behind.
      await settings.put(AppConstants.keyPendingClearAll, true);
      await txRepo.addTransaction(makeTransaction(id: 't1', assetId: 'a1'));
      await txRepo.addTransaction(makeTransaction(id: 't2', assetId: 'a2'));
      await history.put('2026-10-21', '{"total":1000}');
      await settings.put('rebal_stock', 100.0);

      final removed = await service.completeInterruptedWrites();

      expect(removed, 2);
      expect(txRepo.getAllTransactions(), isEmpty);
      expect(history.isEmpty, isTrue);
      expect(settings.get('rebal_stock'), isNull);
      expect(widgetClears, 1);
      expect(settings.get(AppConstants.keyPendingClearAll), isFalse);
    });

    test('works on boxes the service was not handed (the app path)',
        () async {
      // The app constructs the service without overrides; the history and
      // cache boxes are found by name.
      await history.put('2026-10-21', '{"total":1000}');
      await priceCache.put('BTC:INR', '{"price":1}');
      final appService = PortfolioWriteService(
        assetRepository: assetRepo,
        transactionRepository: txRepo,
        settingsBox: settings,
        clearHomeWidget: () async {},
      );

      await appService.clearAllData();

      expect(history.isEmpty, isTrue);
      expect(priceCache.isEmpty, isTrue);
    });
  });

  group('recordSell', () {
    late AssetRepository assetRepo;
    late TransactionRepository txRepo;
    late PortfolioWriteService service;

    /// 10 units bought at 100 on 15 Jan 2024.
    Asset holding({double quantity = 10}) =>
        makeAsset(id: 'a1').copyWith(quantity: quantity, currency: 'USD');

    setUp(() async {
      assetRepo = AssetRepository();
      txRepo = TransactionRepository();
      service = PortfolioWriteService(
        assetRepository: assetRepo,
        transactionRepository: txRepo,
        settingsBox: settings,
      );
      await assetRepo.addAsset(holding());
    });

    test('stores the SELL and lowers the quantity; average cost unchanged',
        () async {
      final sell = await service.recordSell(
        assetId: 'a1',
        quantity: 4,
        pricePerUnit: 130,
        date: DateTime(2024, 6, 1),
        notes: '  partial exit  ',
      );

      final stored = txRepo.getAllTransactions().single;
      expect(stored.id, sell.id);
      expect(stored.type, TransactionType.sell);
      expect(stored.quantity, 4);
      expect(stored.price, 130);
      expect(stored.amount, 520); // proceeds = 4 x 130
      expect(stored.currency, 'USD'); // the holding's currency
      expect(stored.date, DateTime(2024, 6, 1));
      expect(stored.notes, 'partial exit');

      final asset = assetRepo.getAssetById('a1')!;
      expect(asset.quantity, 6);
      expect(asset.purchasePrice, 100);
    });

    test('selling everything keeps the asset at quantity 0', () async {
      // A rounding remainder must not survive as dust.
      await assetRepo.addAsset(holding(quantity: 0.1 + 0.2));

      await service.recordSell(
        assetId: 'a1',
        quantity: 0.3,
        pricePerUnit: 130,
        date: DateTime(2024, 6, 1),
      );

      final asset = assetRepo.getAssetById('a1');
      expect(asset, isNotNull, reason: 'cost basis must stay available');
      expect(asset!.quantity, 0);
    });

    test('rejects an over-sell and writes nothing', () async {
      await expectLater(
        () => service.recordSell(
          assetId: 'a1',
          quantity: 10.5,
          pricePerUnit: 130,
          date: DateTime(2024, 6, 1),
        ),
        throwsA(isA<ArgumentError>()
            .having((e) => e.message, 'message', contains('You hold 10'))),
      );

      expect(txRepo.getAllTransactions(), isEmpty);
      expect(assetRepo.getAssetById('a1')!.quantity, 10);
    });

    test('rejects non-finite or non-positive input and impossible dates',
        () async {
      Future<void> expectRejected(
              {double quantity = 1,
              double price = 130,
              DateTime? date}) =>
          expectLater(
            () => service.recordSell(
              assetId: 'a1',
              quantity: quantity,
              pricePerUnit: price,
              date: date ?? DateTime(2024, 6, 1),
            ),
            throwsA(isA<ArgumentError>()),
          );

      await expectRejected(quantity: 0);
      await expectRejected(quantity: double.nan);
      await expectRejected(price: -5);
      await expectRejected(price: double.infinity);
      await expectRejected(date: DateTime(2023, 12, 31)); // before purchase
      await expectRejected(
          date: DateTime.now().add(const Duration(days: 2))); // future
      expect(txRepo.getAllTransactions(), isEmpty);
    });

    test('rolls the SELL back when lowering the quantity fails', () async {
      final mockAssets = MockAssetRepository();
      final mockTx = MockTransactionRepository();
      registerFallbackValue(makeTransaction(assetId: 'a1'));
      when(() => mockAssets.getAssetById('a1')).thenReturn(holding());
      when(() => mockTx.addTransaction(any())).thenAnswer((_) async {});
      when(() => mockAssets.updateAsset(any()))
          .thenThrow(HiveError('disk full'));
      when(() => mockTx.deleteTransaction(any())).thenAnswer((_) async {});

      final failing = PortfolioWriteService(
        assetRepository: mockAssets,
        transactionRepository: mockTx,
        settingsBox: settings,
      );

      await expectLater(
        () => failing.recordSell(
          assetId: 'a1',
          quantity: 4,
          pricePerUnit: 130,
          date: DateTime(2024, 6, 1),
        ),
        throwsA(isA<HiveError>()),
      );

      final added = verify(() => mockTx.addTransaction(captureAny()))
          .captured
          .single as Transaction;
      verify(() => mockTx.deleteTransaction(added.id)).called(1);
    });

    test('refuses an asset that no longer exists', () async {
      await expectLater(
        () => service.recordSell(
          assetId: 'gone',
          quantity: 1,
          pricePerUnit: 1,
          date: DateTime(2024, 6, 1),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('deleting the SELL gives the units back', () async {
      final sell = await service.recordSell(
        assetId: 'a1',
        quantity: 4,
        pricePerUnit: 130,
        date: DateTime(2024, 6, 1),
      );

      await service.deleteTransaction(txRepo.getAllTransactions().single);

      expect(txRepo.getAllTransactions().where((t) => t.id == sell.id),
          isEmpty);
      expect(assetRepo.getAssetById('a1')!.quantity, 10);
    });
  });

  group('recordIncome', () {
    late AssetRepository assetRepo;
    late TransactionRepository txRepo;
    late PortfolioWriteService service;

    setUp(() async {
      assetRepo = AssetRepository();
      txRepo = TransactionRepository();
      service = PortfolioWriteService(
        assetRepository: assetRepo,
        transactionRepository: txRepo,
        settingsBox: settings,
      );
      await assetRepo.addAsset(makeAsset(id: 'a1'));
    });

    test('stores a dividend without touching the holding', () async {
      await service.recordIncome(
        assetId: 'a1',
        type: TransactionType.dividend,
        amount: 42.5,
        date: DateTime(2024, 3, 1),
      );

      final stored = txRepo.getAllTransactions().single;
      expect(stored.type, TransactionType.dividend);
      expect(stored.amount, 42.5);
      expect(stored.quantity, 0);
      expect(stored.currency, 'INR');
      expect(assetRepo.getAssetById('a1')!.quantity, 1);
    });

    test('only dividend or interest, with a positive amount', () async {
      await expectLater(
        () => service.recordIncome(
            assetId: 'a1',
            type: TransactionType.sell,
            amount: 10,
            date: DateTime(2024, 3, 1)),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        () => service.recordIncome(
            assetId: 'a1',
            type: TransactionType.interest,
            amount: 0,
            date: DateTime(2024, 3, 1)),
        throwsA(isA<ArgumentError>()),
      );
      expect(txRepo.getAllTransactions(), isEmpty);
    });

    test('deleting income only removes the record', () async {
      await service.recordIncome(
        assetId: 'a1',
        type: TransactionType.interest,
        amount: 12,
        date: DateTime(2024, 3, 1),
      );

      await service.deleteTransaction(txRepo.getAllTransactions().single);

      expect(txRepo.getAllTransactions(), isEmpty);
      expect(assetRepo.getAssetById('a1')!.quantity, 1);
    });
  });
}
