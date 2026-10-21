import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:kashu/core/constants/app_constants.dart';
import 'package:kashu/data/models/asset.dart';
import 'package:kashu/data/models/asset_type.dart';
import 'package:kashu/data/models/transaction.dart';
import 'package:kashu/data/models/transaction_type.dart';
import 'package:kashu/features/settings/settings_screen.dart';
import 'package:kashu/services/backup_service.dart';

const _pickerChannel = MethodChannel('miguelruivo.flutter.plugins.filepicker');

Map<String, dynamic> _asset(String id) => Asset(
      id: id,
      name: 'Asset $id',
      type: AssetType.stock,
      quantity: 3,
      purchasePrice: 100,
      currentPrice: 110,
      currency: 'INR',
      purchaseDate: DateTime(2024, 1, 15),
      createdAt: DateTime(2024, 1, 15),
      updatedAt: DateTime(2024, 1, 15),
    ).toJson();

Map<String, dynamic> _transaction(String id, String assetId) => Transaction(
      id: id,
      assetId: assetId,
      type: TransactionType.buy,
      quantity: 3,
      price: 100,
      amount: 300,
      currency: 'INR',
      date: DateTime(2024, 1, 15),
      createdAt: DateTime(2024, 1, 15),
    ).toJson();

void main() {
  late Box<Asset> assets;
  late Box<Transaction> transactions;

  setUpAll(() {
    Hive.registerAdapter(AssetTypeAdapter());
    Hive.registerAdapter(TransactionTypeAdapter());
    Hive.registerAdapter(AssetAdapter());
    Hive.registerAdapter(TransactionAdapter());
  });

  setUp(() async {
    // In-memory boxes: writes complete inside the widget test's fake-async
    // zone without real file I/O.
    assets =
        await Hive.openBox<Asset>(AppConstants.assetsBox, bytes: Uint8List(0));
    transactions = await Hive.openBox<Transaction>(AppConstants.transactionsBox,
        bytes: Uint8List(0));
    await Hive.openBox(AppConstants.settingsBox, bytes: Uint8List(0));
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pickerChannel, null);
    await Hive.close();
  });

  /// The platform file picker hands back [bytes] as the chosen file.
  void pickerReturns(List<int> bytes) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pickerChannel, (call) async {
      return [
        {
          'name': 'kashu_backup.json',
          'path': null,
          'bytes': Uint8List.fromList(bytes),
          'size': bytes.length,
        }
      ];
    });
  }

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pump();
  }

  Future<void> chooseBackupFile(WidgetTester tester) async {
    await tester.tap(find.text('Import Data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose backup file'));
    await tester.pumpAndSettle();
  }

  List<int> backupFile() => utf8.encode(BackupService.encode(
        BackupService.buildEnvelope(
          assets: [_asset('a1'), _asset('a2')],
          transactions: [_transaction('t1', 'a1'), _transaction('t2', 'a2')],
        ),
      ));

  testWidgets('a picked backup file is previewed, then imported on confirm',
      (tester) async {
    pickerReturns(backupFile());
    await pumpSettings(tester);

    await chooseBackupFile(tester);

    expect(find.text('Import this backup?'), findsOneWidget);
    expect(find.textContaining('2 assets and 2 transactions will be added'),
        findsOneWidget);
    expect(assets.isEmpty, isTrue, reason: 'nothing written before confirm');

    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(assets.keys, unorderedEquals(['a1', 'a2']));
    expect(transactions.keys, unorderedEquals(['t1', 't2']));
    expect(find.text('Imported 2 assets and 2 transactions.'), findsOneWidget);
  });

  testWidgets(
      'history of deleted holdings is imported and called out in the preview',
      (tester) async {
    pickerReturns(utf8.encode(BackupService.encode(
      BackupService.buildEnvelope(
        assets: [_asset('a1')],
        transactions: [
          _transaction('t1', 'a1'),
          _transaction('h1', 'deleted-holding'),
          _transaction('h2', 'deleted-holding'),
          _transaction('h3', 'another-deleted-holding'),
        ],
      ),
    )));
    await pumpSettings(tester);

    await chooseBackupFile(tester);

    expect(
        find.textContaining('3 transactions belong to holdings that were '
            'deleted earlier; they are kept as history.'),
        findsOneWidget);

    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(transactions.keys, unorderedEquals(['t1', 'h1', 'h2', 'h3']));
  });

  testWidgets('cancelling the preview writes nothing', (tester) async {
    pickerReturns(backupFile());
    await pumpSettings(tester);

    await chooseBackupFile(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(assets.isEmpty, isTrue);
    expect(transactions.isEmpty, isTrue);
  });

  testWidgets('a corrupted file is refused with a plain message',
      (tester) async {
    final file = backupFile();
    pickerReturns(file.sublist(0, file.length - 40));
    await pumpSettings(tester);

    await chooseBackupFile(tester);

    expect(find.text('Import this backup?'), findsNothing);
    expect(
        find.text('This file is not a KashU backup (it is not valid JSON). '
            'Nothing was imported.'),
        findsOneWidget);
    expect(assets.isEmpty, isTrue);
  });
}
