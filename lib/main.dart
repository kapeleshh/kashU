import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/theme/app_theme.dart';
import 'core/constants/app_strings.dart';
import 'core/constants/app_constants.dart';
import 'data/models/asset_type.dart';
import 'data/models/transaction_type.dart';
import 'data/models/asset.dart';
import 'data/models/transaction.dart';
import 'features/dashboard/dashboard_screen.dart';

/// Secure storage key for the Hive AES encryption key.
const _kHiveEncryptionKey = 'kashu_hive_aes_key';

/// Retrieve the persisted Hive encryption key, or generate + store a new one.
Future<HiveAesCipher> _loadOrCreateCipher() async {
  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final existing = await storage.read(key: _kHiveEncryptionKey);
  List<int> keyBytes;

  if (existing != null) {
    keyBytes = base64Decode(existing);
  } else {
    final rng = Random.secure();
    keyBytes = List<int>.generate(32, (_) => rng.nextInt(256));
    await storage.write(
      key: _kHiveEncryptionKey,
      value: base64Encode(keyBytes),
    );
  }

  return HiveAesCipher(keyBytes);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // Initialize Hive
  await Hive.initFlutter();

  // Register Hive adapters
  Hive.registerAdapter(AssetTypeAdapter());
  Hive.registerAdapter(TransactionTypeAdapter());
  Hive.registerAdapter(AssetAdapter());
  Hive.registerAdapter(TransactionAdapter());

  // Load (or create) the AES cipher backed by flutter_secure_storage.
  // All boxes are encrypted with the same key — the key itself never
  // touches disk unprotected (it lives in the platform keychain/keystore).
  final cipher = await _loadOrCreateCipher();

  // Open Hive boxes with encryption
  await Hive.openBox<Asset>(AppConstants.assetsBox, encryptionCipher: cipher);
  await Hive.openBox<Transaction>(AppConstants.transactionsBox,
      encryptionCipher: cipher);
  await Hive.openBox(AppConstants.settingsBox, encryptionCipher: cipher);
  await Hive.openBox(AppConstants.priceCacheBox, encryptionCipher: cipher);

  runApp(
    const ProviderScope(
      child: KashUApp(),
    ),
  );
}

class KashUApp extends StatelessWidget {
  const KashUApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const DashboardScreen(),
    );
  }
}
