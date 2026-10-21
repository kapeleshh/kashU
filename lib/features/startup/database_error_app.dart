import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_theme.dart';

/// What stopped startup from opening the encrypted database.
enum DatabaseErrorKind {
  /// The encryption key is missing, unreadable or doesn't match the data —
  /// almost always a phone backup or transfer restored onto another device.
  keyUnavailable,

  /// A box failed to open or migrate (damaged file, storage full, ...).
  openFailed,
}

/// Recovery app shown instead of KashU when the database can't be opened.
///
/// Explains what happened in plain words and offers two ways out: try again
/// (a transient keystore or storage hiccup can clear on its own), or reset —
/// behind an in-page confirmation — which deletes the local database and key
/// so the user can start fresh and import a backup file.
class DatabaseErrorApp extends StatelessWidget {
  final DatabaseErrorKind kind;

  /// Technical detail for support, shown small under the explanation.
  final String? detail;

  /// Re-runs startup.
  final VoidCallback onRetry;

  /// Deletes the local database and key, then restarts. Throws on failure.
  final Future<void> Function() onReset;

  const DatabaseErrorApp({
    super.key,
    required this.kind,
    this.detail,
    required this.onRetry,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: DatabaseErrorScreen(
        kind: kind,
        detail: detail,
        onRetry: onRetry,
        onReset: onReset,
      ),
    );
  }
}

class DatabaseErrorScreen extends StatefulWidget {
  final DatabaseErrorKind kind;
  final String? detail;
  final VoidCallback onRetry;
  final Future<void> Function() onReset;

  const DatabaseErrorScreen({
    super.key,
    required this.kind,
    this.detail,
    required this.onRetry,
    required this.onReset,
  });

  @override
  State<DatabaseErrorScreen> createState() => _DatabaseErrorScreenState();
}

enum _Stage { explain, confirm, resetting, resetFailed }

class _DatabaseErrorScreenState extends State<DatabaseErrorScreen> {
  _Stage _stage = _Stage.explain;

  Future<void> _reset() async {
    setState(() => _stage = _Stage.resetting);
    try {
      await widget.onReset();
    } catch (e) {
      debugPrint('[KashU] Reset failed: $e');
      if (mounted) setState(() => _stage = _Stage.resetFailed);
    }
  }

  String get _title => widget.kind == DatabaseErrorKind.keyUnavailable
      ? "KashU can't unlock your data"
      : 'Unable to open database';

  String get _explanation => widget.kind == DatabaseErrorKind.keyUnavailable
      ? 'Your portfolio is encrypted with a key kept in this device\'s secure '
          'storage, and that key can\'t be read right now. This usually '
          'happens after restoring a phone backup or moving to a new phone: '
          'the key never leaves the original device, so data copied from it '
          'can\'t be opened here.\n\n'
          'Close KashU and open it again first. If this screen comes back, '
          'reset KashU, then restore your portfolio from a backup file with '
          'Settings › Import Data.'
      : 'KashU could not open its local database. This can happen if '
          'storage is full or the database file is damaged.\n\n'
          'Free up some storage and try again. If the problem persists, '
          'reset KashU and restore your portfolio from a backup file with '
          'Settings › Import Data.';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.kind == DatabaseErrorKind.keyUnavailable
                      ? Icons.lock_reset
                      : Icons.error_outline,
                  color: scheme.error,
                  size: 64,
                ),
                const SizedBox(height: 24),
                Text(
                  _title,
                  style: AppTheme.heading(
                    size: 22,
                    weight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  _explanation,
                  style: AppTheme.body(
                    size: 14,
                    weight: FontWeight.w500,
                    color: AppColors.textSecondaryOn(context),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                _buildActions(context),
                if (widget.detail != null) ...[
                  const SizedBox(height: 28),
                  Text(
                    widget.detail!,
                    style: AppTheme.body(
                      size: 11,
                      color: AppColors.textTertiaryOn(context),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    switch (_stage) {
      case _Stage.explain:
        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: widget.onRetry,
                child: const Text('Try again'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => _stage = _Stage.confirm),
              child: Text(
                'Reset KashU…',
                style: TextStyle(color: AppColors.lossOn(context)),
              ),
            ),
          ],
        );
      case _Stage.confirm:
        return _ConfirmResetCard(
          onCancel: () => setState(() => _stage = _Stage.explain),
          onConfirm: _reset,
        );
      case _Stage.resetting:
        return const CircularProgressIndicator(color: AppColors.primary);
      case _Stage.resetFailed:
        return Column(
          children: [
            Text(
              'The reset did not finish. Restart your phone and try again.',
              style: AppTheme.body(
                size: 13,
                weight: FontWeight.w600,
                color: Theme.of(context).colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => setState(() => _stage = _Stage.confirm),
              child: const Text('Try the reset again'),
            ),
          ],
        );
    }
  }
}

/// In-page confirmation for the irreversible reset — deliberately not a
/// dialog, so it stays visible next to the explanation it confirms.
class _ConfirmResetCard extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  const _ConfirmResetCard({required this.onCancel, required this.onConfirm});

  // Tighter than the theme's 24px so both labels fit on one line side by
  // side on a phone.
  static const _buttonPadding =
      EdgeInsets.symmetric(horizontal: 8, vertical: 15);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final loss = AppColors.lossOn(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            'Delete all KashU data on this device?',
            style: AppTheme.heading(
              size: 16,
              weight: FontWeight.w700,
              color: scheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'This permanently deletes the portfolio stored in KashU on this '
            'device, and its encryption key. It cannot be undone. Backup '
            'files you exported are not affected — import one from '
            'Settings › Import Data after the reset.',
            style: AppTheme.body(
              size: 13,
              weight: FontWeight.w500,
              color: AppColors.textSecondaryOn(context),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(padding: _buttonPadding),
                  onPressed: onCancel,
                  child: const Text(AppStrings.cancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: loss,
                    padding: _buttonPadding,
                  ),
                  onPressed: onConfirm,
                  child: const Text('Delete and reset'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
