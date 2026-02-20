import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/theme/app_theme.dart';
import 'core/constants/app_strings.dart';
import 'core/constants/app_constants.dart';
import 'data/models/asset_type.dart';
import 'data/models/transaction_type.dart';
import 'data/models/asset.dart';
import 'data/models/transaction.dart';
import 'features/dashboard/dashboard_screen.dart';

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
  
  // Open Hive boxes
  await Hive.openBox<Asset>(AppConstants.assetsBox);
  await Hive.openBox<Transaction>(AppConstants.transactionsBox);
  await Hive.openBox(AppConstants.settingsBox);

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
