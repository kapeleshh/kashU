import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/import_validator.dart';
import '../../services/auth_service.dart';
import '../../shared/providers/portfolio_provider.dart';
import '../rebalancing/rebalancing_screen.dart';
import '../export/tax_export_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _appLockEnabled = false;

  @override
  void initState() {
    super.initState();
    _appLockEnabled = Hive.box(AppConstants.settingsBox)
        .get(AppConstants.keyAppLockEnabled, defaultValue: false) as bool;
  }

  Future<void> _toggleAppLock(bool value) async {
    if (value) {
      // Verify device supports authentication before enabling
      final authService = AuthService();
      final available = await authService.isAvailable();
      final enrolled = await authService.isEnrolled();

      if (!available || !enrolled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No biometrics or PIN set up on this device. '
              'Please configure device security in your system Settings first.',
            ),
          ),
        );
        return;
      }
    }

    await Hive.box(AppConstants.settingsBox)
        .put(AppConstants.keyAppLockEnabled, value);
    if (mounted) setState(() => _appLockEnabled = value);
  }

  @override
  Widget build(BuildContext context) {
    final baseCurrency = ref.watch(baseCurrencyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.settings),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // Preferences Section
          _buildSectionHeader(context, 'Preferences'),
          const SizedBox(height: 11),
          _buildSettingsCard([
            _BaseCurrencyTile(
              currentCurrency: baseCurrency,
              onChanged: (currency) async {
                final assetRepo = ref.read(assetRepositoryProvider);
                await assetRepo.setBaseCurrency(currency);
                ref.read(baseCurrencyProvider.notifier).state = currency;
                ref.invalidate(portfolioSummaryProvider);
              },
            ),
          ]),

          const SizedBox(height: 22),

          // Security Section
          _buildSectionHeader(context, AppStrings.security),
          const SizedBox(height: 11),
          _buildSettingsCard([
            SwitchListTile(
              secondary: _tileIcon(Icons.lock_outline),
              title: Text(
                'Require Authentication',
                style: AppTheme.body(
                  size: 15,
                  weight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              subtitle: Text(
                'Use biometrics or device PIN to unlock the app',
                style: AppTheme.body(
                  size: 12.5,
                  weight: FontWeight.w500,
                  color: AppColors.textTertiaryOn(context),
                ),
              ),
              value: _appLockEnabled,
              activeThumbColor: AppColors.primary,
              activeTrackColor: AppColors.primary.withValues(alpha: 0.4),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              onChanged: _toggleAppLock,
            ),
          ]),

          const SizedBox(height: 22),

          // Portfolio Tools Section
          _buildSectionHeader(context, 'Portfolio Tools'),
          const SizedBox(height: 11),
          _buildSettingsCard([
            _SettingsTile(
              icon: Icons.balance_outlined,
              title: 'Rebalancing Calculator',
              subtitle:
                  'Set target allocations and see what to buy or sell',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const RebalancingScreen()),
              ),
            ),
          ]),

          const SizedBox(height: 22),

          // Data Management Section
          _buildSectionHeader(context, AppStrings.dataManagement),
          const SizedBox(height: 11),
          _buildSettingsCard([
            _SettingsTile(
              icon: Icons.receipt_long_outlined,
              title: 'Tax Export',
              subtitle: 'Export holdings & capital gains as CSV or PDF',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const TaxExportScreen()),
              ),
            ),
            _SettingsTile(
              icon: Icons.upload_outlined,
              title: AppStrings.exportData,
              subtitle: 'Export your portfolio data as JSON',
              onTap: () => _exportData(context, ref),
            ),
            _SettingsTile(
              icon: Icons.download_outlined,
              title: AppStrings.importData,
              subtitle: 'Import portfolio data from JSON',
              onTap: () => _showImportDialog(context, ref),
            ),
            _SettingsTile(
              icon: Icons.delete_outline,
              title: 'Clear All Data',
              subtitle: 'Delete all assets and transactions',
              iconColor: AppColors.lossOn(context),
              destructive: true,
              onTap: () => _showClearDataDialog(context, ref),
            ),
          ]),

          const SizedBox(height: 22),

          // About Section
          _buildSectionHeader(context, AppStrings.about),
          const SizedBox(height: 11),
          _buildSettingsCard([
            _SettingsTile(
              icon: Icons.info_outline,
              title: AppStrings.appName,
              subtitle: 'Version 1.0.0',
              onTap: () => _showAboutDialog(context),
            ),
          ]),

          const SizedBox(height: 32),

          // App Info
          Center(
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(AppRadii.tile),
                    boxShadow: AppShadows.glow(AppColors.primary, opacity: 0.45),
                  ),
                  child: Center(
                    child: Text(
                      'K',
                      style: AppTheme.heading(
                        size: 30,
                        weight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  AppStrings.appName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  AppStrings.appTagline,
                  style: AppTheme.body(
                    size: 13.5,
                    weight: FontWeight.w500,
                    color: AppColors.textSecondaryOn(context),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Small tonal rounded container holding a leading icon.
  Widget _tileIcon(IconData icon, {Color? color}) {
    final tone = color ?? AppColors.primary;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadii.avatar),
      ),
      child: Icon(icon, color: tone, size: 20),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge,
      ),
    );
  }

  /// A soft rounded group/card. Uses a [Material] so the [ListTile] children
  /// keep their ink + correct background in both light and dark themes.
  Widget _buildSettingsCard(List<Widget> children) {
    return Builder(
      builder: (context) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.card),
          boxShadow: AppShadows.soft(opacity: 0.16, y: 10, blur: 24),
        ),
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadii.card),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: children.asMap().entries.map((entry) {
              final index = entry.key;
              final child = entry.value;
              if (index < children.length - 1) {
                return Column(
                  children: [
                    child,
                    Divider(
                      color: Theme.of(context).dividerColor,
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                    ),
                  ],
                );
              }
              return child;
            }).toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _exportData(BuildContext context, WidgetRef ref) async {
    try {
      final assetRepo = ref.read(assetRepositoryProvider);
      final txRepo = ref.read(transactionRepositoryProvider);

      final exportData = {
        'schemaVersion': ImportValidator.currentSchemaVersion,
        'exportedAt': DateTime.now().toIso8601String(),
        'assets': assetRepo.exportToJson(),
        'transactions': txRepo.exportToJson(),
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);
      final directory = await getApplicationDocumentsDirectory();
      final file = File(
          '${directory.path}/kashu_backup_${DateTime.now().millisecondsSinceEpoch}.json');
      await file.writeAsString(jsonString);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'KashU Portfolio Backup',
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.exportSuccess)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  void _showImportDialog(BuildContext context, WidgetRef ref) {
    final textController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.importData),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paste your KashU backup JSON below:',
              style: AppTheme.body(
                size: 13,
                weight: FontWeight.w500,
                color: AppColors.textSecondaryOn(context),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: '{ "version": "1.0", "assets": [...] }',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(AppStrings.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              final json = textController.text.trim();
              if (json.isEmpty) return;

              try {
                final decoded = jsonDecode(json);
                if (decoded is! Map<String, dynamic>) {
                  throw const FormatException(
                      'Top-level JSON must be an object.');
                }
                final data = decoded;

                // Schema validation before touching the database
                final envelopeErr =
                    ImportValidator.validateEnvelope(data);
                if (envelopeErr != null) throw FormatException(envelopeErr);

                final rawAssets =
                    data['assets'] != null ? data['assets'] as List : [];
                final rawTx = data['transactions'] != null
                    ? data['transactions'] as List
                    : [];

                final assetErr =
                    ImportValidator.validateAssets(rawAssets);
                if (assetErr != null) throw FormatException(assetErr);

                final txErr =
                    ImportValidator.validateTransactions(rawTx);
                if (txErr != null) throw FormatException(txErr);

                // All validated — write to database
                final assetRepo = ref.read(assetRepositoryProvider);
                final txRepo = ref.read(transactionRepositoryProvider);

                if (rawAssets.isNotEmpty) {
                  await assetRepo.importFromJson(
                    rawAssets.cast<Map<String, dynamic>>(),
                  );
                }
                if (rawTx.isNotEmpty) {
                  await txRepo.importFromJson(
                    rawTx.cast<Map<String, dynamic>>(),
                  );
                }

                ref.invalidate(allAssetsProvider);
                ref.invalidate(portfolioSummaryProvider);

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Imported ${rawAssets.length} assets and '
                        '${rawTx.length} transactions.',
                      ),
                    ),
                  );
                }
              } on FormatException catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Import failed: ${e.message}'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Import failed: $e'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  void _showClearDataDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Data'),
        content: const Text(
          'This will permanently delete all your assets and transactions. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(AppStrings.cancel),
          ),
          TextButton(
            onPressed: () async {
              final assetRepo = ref.read(assetRepositoryProvider);
              final txRepo = ref.read(transactionRepositoryProvider);
              await assetRepo.clearAll();
              await txRepo.clearAll();

              ref.invalidate(portfolioSummaryProvider);
              ref.invalidate(allAssetsProvider);

              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('All data cleared')),
                );
              }
            },
            child: Text(
              'Clear All',
              style: TextStyle(color: AppColors.lossOn(context)),
            ),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(AppRadii.avatar),
              ),
              child: Center(
                child: Text(
                  'K',
                  style: AppTheme.heading(
                    size: 22,
                    weight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Text(AppStrings.appName),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.appTagline,
              style: AppTheme.body(
                size: 14,
                weight: FontWeight.w500,
                color: AppColors.textSecondaryOn(context),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Version 1.0.0'),
            const SizedBox(height: 8),
            const Text('Track all your investments in one place.'),
            const SizedBox(height: 8),
            Text(
              '• Stocks, Mutual Funds, Gold, Crypto\n'
              '• Multiple currencies support\n'
              '• Offline-first, privacy-focused\n'
              '• Export & backup your data',
              style: AppTheme.body(
                size: 13,
                weight: FontWeight.w500,
                color: AppColors.textSecondaryOn(context),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/// Tile for selecting the base display currency
class _BaseCurrencyTile extends StatelessWidget {
  final String currentCurrency;
  final ValueChanged<String> onChanged;

  const _BaseCurrencyTile({
    required this.currentCurrency,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppRadii.avatar),
        ),
        child: Icon(Icons.currency_exchange, color: AppColors.primary, size: 20),
      ),
      title: Text(
        'Base Currency',
        style: AppTheme.body(
          size: 15,
          weight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      subtitle: Text(
        '$currentCurrency (${AppConstants.currencies[currentCurrency] ?? currentCurrency})',
        style: AppTheme.body(
          size: 12.5,
          weight: FontWeight.w500,
          color: AppColors.textTertiaryOn(context),
        ),
      ),
      trailing: Icon(Icons.chevron_right,
          color: AppColors.textTertiaryOn(context)),
      onTap: () => _showCurrencyPicker(context),
    );
  }

  void _showCurrencyPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textTertiaryOn(context).withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Select Base Currency',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: AppConstants.currencies.entries.map((entry) {
                  final isSelected = entry.key == currentCurrency;
                  return ListTile(
                    leading: Text(
                      entry.value,
                      style: const TextStyle(fontSize: 22),
                    ),
                    title: Text(
                      entry.key,
                      style: AppTheme.body(
                        size: 15,
                        weight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    subtitle: Text(
                      _currencyName(entry.key),
                      style: AppTheme.body(
                        size: 12.5,
                        weight: FontWeight.w500,
                        color: AppColors.textSecondaryOn(context),
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_circle, color: AppColors.primary)
                        : null,
                    selected: isSelected,
                    onTap: () {
                      onChanged(entry.key);
                      Navigator.pop(context);
                    },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  String _currencyName(String code) {
    const names = {
      'INR': 'Indian Rupee',
      'USD': 'US Dollar',
      'EUR': 'Euro',
      'GBP': 'British Pound',
      'JPY': 'Japanese Yen',
      'AED': 'UAE Dirham',
      'SGD': 'Singapore Dollar',
      'AUD': 'Australian Dollar',
      'CAD': 'Canadian Dollar',
      'CHF': 'Swiss Franc',
    };
    return names[code] ?? code;
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? iconColor;
  final bool destructive;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final tone = iconColor ?? AppColors.primary;
    final titleColor = destructive
        ? AppColors.lossOn(context)
        : Theme.of(context).colorScheme.onSurface;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppRadii.avatar),
        ),
        child: Icon(
          icon,
          color: tone,
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: AppTheme.body(
          size: 15,
          weight: FontWeight.w700,
          color: titleColor,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: AppTheme.body(
          size: 12.5,
          weight: FontWeight.w500,
          color: AppColors.textTertiaryOn(context),
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: AppColors.textTertiaryOn(context),
      ),
      onTap: onTap,
    );
  }
}
