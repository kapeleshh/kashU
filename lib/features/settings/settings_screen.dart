import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_strings.dart';
import '../../shared/providers/portfolio_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baseCurrency = ref.watch(baseCurrencyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.settings),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Preferences Section
          _buildSectionHeader(context, 'Preferences'),
          const SizedBox(height: 8),
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

          const SizedBox(height: 24),

          // Data Management Section
          _buildSectionHeader(context, AppStrings.dataManagement),
          const SizedBox(height: 8),
          _buildSettingsCard([
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
              iconColor: AppColors.error,
              onTap: () => _showClearDataDialog(context, ref),
            ),
          ]),

          const SizedBox(height: 24),

          // About Section
          _buildSectionHeader(context, AppStrings.about),
          const SizedBox(height: 8),
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
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: Text(
                      'K',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  AppStrings.appName,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppStrings.appTagline,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
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

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
    );
  }

  Widget _buildSettingsCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: children.asMap().entries.map((entry) {
          final index = entry.key;
          final child = entry.value;
          if (index < children.length - 1) {
            return Column(
              children: [
                child,
                Divider(color: AppColors.divider, height: 1),
              ],
            );
          }
          return child;
        }).toList(),
      ),
    );
  }

  Future<void> _exportData(BuildContext context, WidgetRef ref) async {
    try {
      final assetRepo = ref.read(assetRepositoryProvider);
      final txRepo = ref.read(transactionRepositoryProvider);

      final exportData = {
        'version': '1.0',
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
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
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
                final data = jsonDecode(json) as Map<String, dynamic>;
                final assetRepo = ref.read(assetRepositoryProvider);
                final txRepo = ref.read(transactionRepositoryProvider);

                if (data['assets'] != null) {
                  await assetRepo.importFromJson(
                    List<Map<String, dynamic>>.from(data['assets'] as List),
                  );
                }
                if (data['transactions'] != null) {
                  await txRepo.importFromJson(
                    List<Map<String, dynamic>>.from(
                        data['transactions'] as List),
                  );
                }

                ref.invalidate(allAssetsProvider);
                ref.invalidate(portfolioSummaryProvider);

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Import successful!')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Import failed: invalid JSON - $e')),
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
              style: TextStyle(color: AppColors.error),
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
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text(
                  'K',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
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
              style: TextStyle(color: AppColors.textSecondary),
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
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
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
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.currency_exchange, color: AppColors.primary, size: 20),
      ),
      title: const Text('Base Currency'),
      subtitle: Text(
        '$currentCurrency (${AppConstants.currencies[currentCurrency] ?? currentCurrency})',
        style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
      ),
      trailing: Icon(Icons.chevron_right, color: AppColors.textTertiary),
      onTap: () => _showCurrencyPicker(context),
    );
  }

  void _showCurrencyPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          Text(
            'Select Base Currency',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
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
                  title: Text(entry.key),
                  subtitle: Text(_currencyName(entry.key)),
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

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: (iconColor ?? AppColors.primary).withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: iconColor ?? AppColors.primary,
          size: 20,
        ),
      ),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: AppColors.textTertiary,
          fontSize: 13,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: AppColors.textTertiary,
      ),
      onTap: onTap,
    );
  }
}
