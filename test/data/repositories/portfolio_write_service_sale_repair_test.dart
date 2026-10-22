import 'dart:async';
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

/// 10 units bought at 100 on 15 Jan 2024.
Asset makeHolding({double quantity = 10}) {
  final when = DateTime(2024, 1, 15);
  return Asset(
    id: 'a1',
    name: 'Reliance',
    type: AssetType.stock,
    quantity: quantity,
    purchasePrice: 100,
    currentPrice: 130,
    currency: 'INR',
    purchaseDate: when,
    createdAt: when,
    updatedAt: when,
  );
}

/// The process is killed while the holding's quantity is being written: the
/// write never lands and nothing after it runs. [reached] completes once the
/// write is attempted, i.e. once everything before it has landed.
class KilledDuringAssetWrite extends AssetRepository {
  final reached = Completer<void>();

  @override
  Future<void> updateAsset(Asset asset) {
    reached.complete();
    return Completer<void>().future; // never returns
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

  /// Close and reopen every box, as a relaunch does: the journal has to
  /// survive the trip through Hive (it comes back as Map<dynamic, dynamic>).
  Future<void> relaunch() async {
    await Hive.close();
    await openBoxes();
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kashu_sale_repair_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(AssetTypeAdapter().typeId)) {
      Hive.registerAdapter(AssetTypeAdapter());
      Hive.registerAdapter(TransactionTypeAdapter());
      Hive.registerAdapter(AssetAdapter());
      Hive.registerAdapter(TransactionAdapter());
    }
    await openBoxes();
    await assetRepo.addAsset(makeHolding());
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  PortfolioWriteService service({AssetRepository? assets}) =>
      PortfolioWriteService(
        assetRepository: assets ?? assetRepo,
        transactionRepository: txRepo,
        settingsBox: settings,
      );

  double quantity() => assetRepo.getAssetById('a1')!.quantity;
  List<Transaction> sells() =>
      txRepo.getTransactionsByType(TransactionType.sell);
  Object? journal() => settings.get(AppConstants.keyPendingSales);

  Future<Transaction> sell4() => service().recordSell(
        assetId: 'a1',
        quantity: 4,
        pricePerUnit: 130,
        date: DateTime(2024, 6, 1),
      );

  group('a sale the app was killed in the middle of', () {
    test('is rolled back at the next launch: no SELL, units still held',
        () async {
      final dying = KilledDuringAssetWrite();
      unawaited(service(assets: dying).recordSell(
        assetId: 'a1',
        quantity: 4,
        pricePerUnit: 130,
        date: DateTime(2024, 6, 1),
      ));
      await dying.reached.future;

      await relaunch();
      // The half-written state the crash left behind.
      expect(sells(), hasLength(1));
      expect(quantity(), 10);
      expect(journal(), isNotNull);

      final removed = await service().completeInterruptedWrites();

      expect(removed, 1);
      expect(sells(), isEmpty);
      expect(quantity(), 10);
      expect(journal(), isNull);
    });

    test(
        'killed after both writes but before the journal was cleared, '
        'is rolled back too — the user never saw it confirmed', () async {
      // Both halves landed; the journal entry is what recordSell writes.
      final sell = Transaction(
        id: 's1',
        assetId: 'a1',
        type: TransactionType.sell,
        quantity: 10,
        price: 130,
        amount: 1300,
        currency: 'INR',
        date: DateTime(2024, 6, 1),
        createdAt: DateTime(2024, 6, 1),
      );
      await settings.put(AppConstants.keyPendingSales, {
        's1': {'op': 'record', 'assetId': 'a1', 'previousQuantity': 10.0},
      });
      await txRepo.addTransaction(sell);
      await assetRepo.updateAsset(makeHolding(quantity: 0)); // full exit
      await relaunch();

      await service().completeInterruptedWrites();

      expect(sells(), isEmpty);
      expect(quantity(), 10);
      expect(journal(), isNull);
    });

    test('a repair that is itself interrupted is finished by the next one',
        () async {
      // Both halves of the sale landed, the journal was not yet cleared.
      final sold = await sell4();
      await settings.put(AppConstants.keyPendingSales, {
        sold.id: {'op': 'record', 'assetId': 'a1', 'previousQuantity': 10.0},
      });
      await relaunch();

      // Launch 2: the repair removes the SELL, then dies restoring units.
      final dying = KilledDuringAssetWrite();
      unawaited(service(assets: dying).completeInterruptedWrites());
      await dying.reached.future;
      await relaunch();
      expect(sells(), isEmpty);
      expect(quantity(), 6);
      expect(journal(), isNotNull);

      // Launch 3 finishes it.
      await service().completeInterruptedWrites();

      expect(sells(), isEmpty);
      expect(quantity(), 10);
      expect(journal(), isNull);
    });
  });

  group('deleting a SELL the app was killed in the middle of', () {
    test('is rolled back at the next launch: the SELL is back, units unchanged',
        () async {
      final sold = await sell4();
      expect(quantity(), 6);

      final dying = KilledDuringAssetWrite();
      unawaited(service(assets: dying).deleteTransaction(sells().single));
      await dying.reached.future;

      await relaunch();
      // The SELL is gone but its units were never given back.
      expect(sells(), isEmpty);
      expect(quantity(), 6);

      final removed = await service().completeInterruptedWrites();

      expect(removed, 0);
      final restored = sells().single;
      expect(restored.id, sold.id);
      expect(restored.quantity, 4);
      expect(restored.amount, 520);
      expect(restored.date, DateTime(2024, 6, 1));
      expect(quantity(), 6);
      expect(journal(), isNull);
    });

    test('killed after the units were given back, is rolled back as well',
        () async {
      final sold = await sell4();
      await settings.put(AppConstants.keyPendingSales, {
        sold.id: {
          'op': 'delete',
          'assetId': 'a1',
          'previousQuantity': 6.0,
          'transaction': sold.toJson(),
        },
      });
      await txRepo.deleteTransaction(sold.id);
      await assetRepo.updateAsset(makeHolding(quantity: 10));
      await relaunch();

      await service().completeInterruptedWrites();

      expect(sells().single.id, sold.id);
      expect(quantity(), 6);
      expect(journal(), isNull);
    });
  });

  test('completed sales and deletes leave no journal behind', () async {
    final sold = await sell4();
    expect(journal(), isNull);

    await service().deleteTransaction(sells().single);
    expect(journal(), isNull);

    expect(await service().completeInterruptedWrites(), 0);
    expect(sells().where((t) => t.id == sold.id), isEmpty);
    expect(quantity(), 10);
  });

  test('an unreadable journal does not stop the app from starting', () async {
    await settings.put(AppConstants.keyPendingSales, {
      'junk': 42,
      's2': {'op': 'delete', 'assetId': 'a1', 'transaction': 'not a map'},
    });

    await expectLater(service().completeInterruptedWrites(), completes);

    expect(journal(), isNull);
    expect(quantity(), 10);
  });

  test('Clear All Data drops the sale journal with everything else', () async {
    await settings.put(AppConstants.keyPendingSales, {
      's1': {'op': 'record', 'assetId': 'a1', 'previousQuantity': 10.0},
    });

    await PortfolioWriteService(
      assetRepository: assetRepo,
      transactionRepository: txRepo,
      settingsBox: settings,
      clearHomeWidget: () async {},
    ).clearAllData();

    expect(journal(), isNull);
  });
}
