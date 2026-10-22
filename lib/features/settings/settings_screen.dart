import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/config/crash_reporting_consent.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/file_saver.dart';
import '../../services/auth_service.dart';
import '../../services/backup_service.dart';
import '../../shared/providers/portfolio_provider.dart';
import '../../shared/providers/settings_providers.dart';
import '../rebalancing/rebalancing_screen.dart';
import '../export/tax_export_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _appLockEnabled = false;

  /// True while the app-lock toggle waits on the authentication prompt, so
  /// a second tap can't stack another prompt or race the first save.
  bool _appLockBusy = false;
  bool _crashReportingEnabled = false;

  @override
  void initState() {
    super.initState();
    final settings = Hive.box(AppConstants.settingsBox);
    _appLockEnabled = settings.get(AppConstants.keyAppLockEnabled,
        defaultValue: false) as bool;
    _crashReportingEnabled = crashReportingConsentGiven(
        settings.get(AppConstants.keyCrashReportingEnabled));
  }

  Future<void> _toggleCrashReporting(bool value) async {
    await Hive.box(AppConstants.settingsBox)
        .put(AppConstants.keyCrashReportingEnabled, value);
    if (mounted) setState(() => _crashReportingEnabled = value);
  }

  Future<void> _toggleAppLock(bool value) async {
    if (_appLockBusy) return;
    setState(() => _appLockBusy = true);
    try {
      final result = await ref.read(authServiceProvider).authenticate(
            reason: value
                ? 'Confirm to turn on app lock'
                : 'Confirm to turn off app lock',
          );
      if (!mounted) return;

      // Turning the lock on must prove this device can actually unlock it —
      // saving the flag on faith is how an Android setup that could never
      // authenticate locked people out of their data. Turning it off needs
      // proof too (anyone holding the unlocked phone could flip it), except
      // when the device can't authenticate at all: the lock is inert then,
      // and refusing would leave the setting stuck on.
      final allowed = result == AuthResult.success ||
          (!value && result.deviceCannotAuthenticate);
      if (!allowed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_appLockRefusal(result, enabling: value))),
        );
        return;
      }

      await Hive.box(AppConstants.settingsBox)
          .put(AppConstants.keyAppLockEnabled, value);
      if (mounted) setState(() => _appLockEnabled = value);
    } finally {
      if (mounted) setState(() => _appLockBusy = false);
    }
  }

  /// Why the app-lock switch did not move, for a non-success [result].
  String _appLockRefusal(AuthResult result, {required bool enabling}) {
    switch (result) {
      case AuthResult.notAvailable:
      case AuthResult.notEnrolled:
        return 'No screen lock is set up on this device. Add a PIN, pattern, '
            'password or fingerprint in your device Settings first.';
      case AuthResult.lockedOut:
        return AppStrings.authLockedOut;
      case AuthResult.permanentlyLockedOut:
        return AppStrings.authPermanentlyLockedOut;
      case AuthResult.error:
        return 'This device could not run authentication, so app lock '
            'was not turned on.';
      case AuthResult.success:
      case AuthResult.failure:
      case AuthResult.cancelled:
        return enabling
            ? 'App lock was not turned on — authentication was not completed.'
            : 'App lock is still on — authentication was not completed.';
    }
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
          // Preferences & Security Section
          _buildSectionHeader(context, 'Preferences & Security'),
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
            // Browsers expose no biometric/PIN API to local_auth, so the
            // lock can never actually engage on web — don't offer it.
            if (!kIsWeb)
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
                onChanged: _appLockBusy ? null : _toggleAppLock,
              ),
            // A build without a Sentry DSN can't send reports, so the
            // opt-in would be a switch that does nothing — don't offer it.
            if (ref.watch(crashReportingAvailableProvider))
              SwitchListTile(
                secondary: _tileIcon(Icons.bug_report_outlined),
                title: Text(
                  'Help improve KashU',
                  style: AppTheme.body(
                    size: 15,
                    weight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                subtitle: Text(
                  'Anonymous crash reports (applies after restart)',
                  style: AppTheme.body(
                    size: 12.5,
                    weight: FontWeight.w500,
                    color: AppColors.textTertiaryOn(context),
                  ),
                ),
                value: _crashReportingEnabled,
                activeThumbColor: AppColors.primary,
                activeTrackColor: AppColors.primary.withValues(alpha: 0.4),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                onChanged: _toggleCrashReporting,
              ),
          ]),

          const SizedBox(height: 22),

          // Appearance Section — applies at once, no restart.
          _buildSectionHeader(context, 'Appearance'),
          const SizedBox(height: 11),
          RadioGroup<ThemeMode>(
            groupValue: ref.watch(themeModeProvider),
            onChanged: (mode) {
              if (mode == null) return;
              ref.read(themeModeProvider.notifier).setThemeMode(mode);
            },
            child: _buildSettingsCard([
              _themeModeTile(
                mode: ThemeMode.system,
                icon: Icons.brightness_auto_outlined,
                title: 'System',
                subtitle: "Match your phone's light or dark setting",
              ),
              _themeModeTile(
                mode: ThemeMode.light,
                icon: Icons.light_mode_outlined,
                title: 'Light',
                subtitle: 'Always use the light theme',
              ),
              _themeModeTile(
                mode: ThemeMode.dark,
                icon: Icons.dark_mode_outlined,
                title: 'Dark',
                subtitle: 'Always use the dark theme',
              ),
            ]),
          ),

          const SizedBox(height: 22),

          // Tools Section
          _buildSectionHeader(context, 'Tools'),
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
          ]),

          const SizedBox(height: 22),

          // Data Management Section
          _buildSectionHeader(context, AppStrings.dataManagement),
          const SizedBox(height: 11),
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
              subtitle: 'Restore from a KashU backup file',
              onTap: _importData,
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
          _buildSectionHeader(context, 'About'),
          const SizedBox(height: 11),
          _buildSettingsCard([
            _SettingsTile(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy Policy',
              subtitle: 'What KashU stores, and what it never collects',
              onTap: () => _openOrCopy(
                Uri.parse(AppConstants.privacyPolicyUrl),
                AppConstants.privacyPolicyUrl,
              ),
            ),
            _SettingsTile(
              icon: Icons.mail_outline,
              title: 'Contact',
              subtitle: AppConstants.contactEmail,
              onTap: () => _openOrCopy(
                Uri(
                  scheme: 'mailto',
                  path: AppConstants.contactEmail,
                  query: 'subject=KashU',
                ),
                AppConstants.contactEmail,
              ),
            ),
            // Flutter's licence page: every package's licence plus the
            // bundled fonts' OFL texts (registered in main()).
            _SettingsTile(
              icon: Icons.description_outlined,
              title: 'Open-source licences',
              subtitle: 'The fonts and libraries KashU is built with',
              onTap: () => showLicensePage(
                context: context,
                applicationName: AppStrings.appName,
              ),
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
                const SizedBox(height: 4),
                Text(
                  'v1.0.0',
                  style: AppTheme.body(
                    size: 12,
                    weight: FontWeight.w500,
                    color: AppColors.textTertiaryOn(context),
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

  /// One choice in the Appearance card. The enclosing [RadioGroup] holds the
  /// selection, so the tile only needs its [mode].
  Widget _themeModeTile({
    required ThemeMode mode,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return RadioListTile<ThemeMode>(
      value: mode,
      secondary: _tileIcon(icon),
      controlAffinity: ListTileControlAffinity.trailing,
      activeColor: AppColors.primary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      title: Text(
        title,
        style: AppTheme.body(
          size: 15,
          weight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurface,
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

      final jsonString = BackupService.encode(BackupService.buildEnvelope(
        assets: assetRepo.exportToJson(),
        transactions: txRepo.exportToJson(),
      ));
      await saveAndShare(
        bytes: Uint8List.fromList(utf8.encode(jsonString)),
        filename:
            'kashu_backup_${DateTime.now().millisecondsSinceEpoch}.json',
        mimeType: 'application/json',
        subject: 'KashU Portfolio Backup',
      );

      // Record the export so the dashboard backup nudge stays quiet.
      await Hive.box(AppConstants.settingsBox).put(
        AppConstants.keyLastExportAt,
        DateTime.now().toIso8601String(),
      );
      ref.invalidate(isBackupOverdueProvider);

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

  /// Open [uri] in the browser or mail app. Where nothing can handle it (no
  /// mail app set up, a locked-down browser), copy [fallback] instead so the
  /// tap is never a dead end.
  Future<void> _openOrCopy(Uri uri, String fallback) async {
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[KashU] Could not open $uri: $e');
    }
    if (opened || !mounted) return;
    await Clipboard.setData(ClipboardData(text: fallback));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied $fallback')),
    );
  }

  /// Import Data: read a backup (the exported file, or pasted text), check
  /// all of it, show what it will change, and only then write it — as one
  /// all-or-nothing import, so a bad file never leaves half its data behind.
  Future<void> _importData() async {
    // Captured up front: the writes and refreshes below must happen even if
    // this screen is gone by the time the user has confirmed.
    final container = ProviderScope.containerOf(context, listen: false);

    final source = await showModalBottomSheet<_ImportSource>(
      context: context,
      builder: (context) => const _ImportSourceSheet(),
    );
    if (source == null || !mounted) return;

    final existingAssetIds = container
        .read(assetRepositoryProvider)
        .getAllAssets()
        .map((a) => a.id)
        .toSet();

    final ParsedBackup backup;
    try {
      final parsed = source == _ImportSource.file
          ? await _readBackupFile(existingAssetIds)
          : await _readPastedBackup(existingAssetIds);
      if (parsed == null) return; // picker or dialog dismissed
      backup = parsed;
    } on FormatException catch (e) {
      _showImportError('${e.message} Nothing was imported.');
      return;
    } catch (e) {
      debugPrint('[KashU] Reading the backup failed: $e');
      _showImportError("Couldn't read that file. Nothing was imported.");
      return;
    }
    if (!mounted) return;

    final confirmed = await _confirmImport(backup, existingAssetIds);
    if (confirmed != true) return;

    try {
      await container.read(portfolioWriteServiceProvider).importBackup(
            assets: backup.assets,
            transactions: backup.transactions,
          );
    } catch (e) {
      debugPrint('[KashU] Import write failed: $e');
      _showImportError('Saving the backup failed, so nothing was changed. '
          'Check that the device has free storage, then try again.');
      return;
    } finally {
      // Providers don't observe Hive — refresh even after a rollback.
      container.invalidate(allAssetsProvider);
      container.invalidate(portfolioSummaryProvider);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Imported ${_count(backup.assets.length, 'asset')} and '
          '${_count(backup.transactions.length, 'transaction')}.'),
    ));
  }

  Future<ParsedBackup?> _readBackupFile(Set<String> existingAssetIds) async {
    // Bytes, never a path: web has no file paths, and on Android the picked
    // document may be a content URI. Any file type rather than a .json
    // filter, because file providers often label a downloaded or shared
    // .json as text/plain and a filter would grey the backup out — the
    // content is validated in full anyway.
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Choose a KashU backup',
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final bytes = result.files.single.bytes;
    if (bytes == null) {
      throw const FormatException("Couldn't read that file.");
    }
    return BackupService.parseBytes(bytes, existingAssetIds: existingAssetIds);
  }

  Future<ParsedBackup?> _readPastedBackup(Set<String> existingAssetIds) async {
    final text = await showDialog<String>(
      context: context,
      builder: (context) => const _PasteBackupDialog(),
    );
    if (text == null || text.trim().isEmpty) return null;
    return BackupService.parse(text, existingAssetIds: existingAssetIds);
  }

  Future<bool?> _confirmImport(
      ParsedBackup backup, Set<String> existingAssetIds) {
    final replaced =
        backup.assets.where((a) => existingAssetIds.contains(a.id)).length;
    final exportedAt = backup.exportedAt;
    final summary = [
      if (exportedAt != null)
        'Backup from ${DateFormat.yMMMd().add_jm().format(exportedAt.toLocal())}.',
      '${_count(backup.assets.length, 'asset')} and '
          '${_count(backup.transactions.length, 'transaction')} will be '
          'added or updated.',
      if (replaced > 0)
        '${_count(replaced, 'asset')} already in KashU will be replaced by '
            "the backup's version.",
      if (backup.historyOnlyTransactions == 1)
        '1 transaction belongs to a holding that was deleted earlier; it is '
            'kept as history.'
      else if (backup.historyOnlyTransactions > 1)
        '${backup.historyOnlyTransactions} transactions belong to holdings '
            'that were deleted earlier; they are kept as history.',
      'Nothing else is changed or deleted.',
    ].join('\n\n');

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import this backup?'),
        content: Text(summary),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(AppStrings.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  void _showImportError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: AppColors.lossOn(context),
    ));
  }

  static String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

  void _showClearDataDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Data'),
        content: const Text(
          'This will permanently delete all your assets and transactions, '
          'their price history and your rebalancing targets. Your settings '
          'are kept. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(AppStrings.cancel),
          ),
          TextButton(
            onPressed: () async {
              // One logical write: pending-clear marker, every portfolio box
              // and setting, the home-screen widget — completed at startup
              // if interrupted.
              var cleared = true;
              try {
                await ref.read(portfolioWriteServiceProvider).clearAllData();
              } catch (e) {
                cleared = false;
                debugPrint('[KashU] Clear All Data failed: $e');
              }

              // Either way: a failed clear may still have removed some data.
              ref.invalidate(portfolioSummaryProvider);
              ref.invalidate(allAssetsProvider);
              ref.invalidate(lastRefreshResultProvider);

              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  cleared
                      ? const SnackBar(content: Text('All data cleared'))
                      : SnackBar(
                          content: const Text(
                            "Couldn't clear all your data. Please try again.",
                          ),
                          backgroundColor: AppColors.lossOn(context),
                        ),
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

enum _ImportSource { file, paste }

/// Where to import from: the exported backup file (primary), or its text
/// pasted in (a fallback when the file can't be reached from this device).
class _ImportSourceSheet extends StatelessWidget {
  const _ImportSourceSheet();

  @override
  Widget build(BuildContext context) {
    Widget option({
      required IconData icon,
      required String title,
      required String subtitle,
      required _ImportSource source,
    }) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppRadii.avatar),
          ),
          child: Icon(icon, color: AppColors.primary, size: 20),
        ),
        title: Text(
          title,
          style: AppTheme.body(
            size: 15,
            weight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
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
        onTap: () => Navigator.pop(context, source),
      );
    }

    return SafeArea(
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
            AppStrings.importData,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          option(
            icon: Icons.file_open_outlined,
            title: 'Choose backup file',
            subtitle: 'The .json file saved by Export Data',
            source: _ImportSource.file,
          ),
          option(
            icon: Icons.content_paste,
            title: 'Paste backup text',
            subtitle: "If you can't reach the file from this device",
            source: _ImportSource.paste,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Collects pasted backup JSON; pops with the text, or null on cancel.
class _PasteBackupDialog extends StatefulWidget {
  const _PasteBackupDialog();

  @override
  State<_PasteBackupDialog> createState() => _PasteBackupDialogState();
}

class _PasteBackupDialogState extends State<_PasteBackupDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Paste backup text'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Paste the full contents of your KashU backup file:',
            style: AppTheme.body(
              size: 13,
              weight: FontWeight.w500,
              color: AppColors.textSecondaryOn(context),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLines: 6,
            decoration: const InputDecoration(
              // Must match the real export envelope (ImportValidator
              // rejects a bare "version" key).
              hintText:
                  '{ "schemaVersion": ${AppConstants.backupFormatVersion}, "assets": [...] }',
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
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
