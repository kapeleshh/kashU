import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_theme.dart';
import '../../services/export_service.dart';
import '../../shared/providers/portfolio_provider.dart';

class TaxExportScreen extends ConsumerStatefulWidget {
  const TaxExportScreen({super.key});

  @override
  ConsumerState<TaxExportScreen> createState() => _TaxExportScreenState();
}

class _TaxExportScreenState extends ConsumerState<TaxExportScreen> {
  bool _isExporting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Export for Tax Filing'),
      ),
      body: _isExporting
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(AppRadii.tile),
                      boxShadow:
                          AppShadows.glow(AppColors.primary, opacity: 0.5),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.6,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Generating export…',
                    style: AppTheme.body(
                      size: 14,
                      weight: FontWeight.w600,
                      color: AppColors.textSecondaryOn(context),
                    ),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                const _InfoCard(),
                const SizedBox(height: 24),
                _SectionHeader('CSV Exports'),
                const SizedBox(height: 11),
                _ExportGroup(
                  children: [
                    _ExportTile(
                      icon: Icons.table_chart_outlined,
                      tone: AppColors.stockColor,
                      title: 'Holdings CSV',
                      subtitle:
                          'All current holdings with cost basis and P&L',
                      onTap: () => _export(_exportHoldings),
                    ),
                    _ExportTile(
                      icon: Icons.receipt_long_outlined,
                      tone: AppColors.bondColor,
                      title: 'Transactions CSV',
                      subtitle:
                          'Full transaction history — buy, sell, dividends',
                      onTap: () => _export(_exportTransactions),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _SectionHeader('PDF Report'),
                const SizedBox(height: 11),
                _ExportGroup(
                  children: [
                    _ExportTile(
                      icon: Icons.picture_as_pdf_outlined,
                      tone: AppColors.cryptoColor,
                      title: 'Capital Gains Report (PDF)',
                      subtitle:
                          'Holdings, capital gains summary (STCG/LTCG), and full transaction log. Share with your CA.',
                      onTap: () => _export(_exportPdf),
                    ),
                    _ExportTile(
                      icon: Icons.preview_outlined,
                      tone: AppColors.fdColor,
                      title: 'Preview PDF',
                      subtitle: 'Preview the report before exporting',
                      onTap: () => _export(_previewPdf),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const _Disclaimer(),
              ],
            ),
    );
  }

  Future<void> _export(Future<void> Function() action) async {
    setState(() => _isExporting = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportHoldings() async {
    final assets = ref.read(allAssetsProvider);
    await ExportService.exportHoldingsCsv(assets);
  }

  Future<void> _exportTransactions() async {
    final assets = ref.read(allAssetsProvider);
    final txRepo = ref.read(transactionRepositoryProvider);
    final transactions = txRepo.getAllTransactions();
    final assetNames = {for (final a in assets) a.id: a.name};
    await ExportService.exportTransactionsCsv(transactions, assetNames);
  }

  Future<void> _exportPdf() async {
    final assets = ref.read(allAssetsProvider);
    final txRepo = ref.read(transactionRepositoryProvider);
    final transactions = txRepo.getAllTransactions();
    final assetNames = {for (final a in assets) a.id: a.name};
    final baseCurrency = ref.read(baseCurrencyProvider);
    await ExportService.exportCapitalGainsPdf(
        assets, transactions, assetNames, baseCurrency);
  }

  Future<void> _previewPdf() async {
    final assets = ref.read(allAssetsProvider);
    final txRepo = ref.read(transactionRepositoryProvider);
    final transactions = txRepo.getAllTransactions();
    final assetNames = {for (final a in assets) a.id: a.name};
    final baseCurrency = ref.read(baseCurrencyProvider);
    await ExportService.previewCapitalGainsPdf(
        assets, transactions, assetNames, baseCurrency);
  }
}

/// Soft gradient hero explaining what these exports do.
class _InfoCard extends StatelessWidget {
  const _InfoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(AppRadii.hero),
        boxShadow: AppShadows.glow(AppColors.primary, opacity: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppRadii.avatar),
                ),
                child: const Icon(Icons.description_outlined,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Tax-ready exports',
                  style: AppTheme.heading(
                    size: 18,
                    weight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Generate CSV or PDF reports of your portfolio for tax filing. '
            'The capital gains report calculates STCG (< 1 year) and '
            'LTCG (≥ 1 year) based on your transaction history.',
            style: AppTheme.body(
              size: 13,
              weight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge,
      ),
    );
  }
}

/// A soft rounded group holding [_ExportTile] rows, divided in both modes.
class _ExportGroup extends StatelessWidget {
  final List<Widget> children;
  const _ExportGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}

class _ExportTile extends StatelessWidget {
  final IconData icon;
  final Color tone;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ExportTile({
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppRadii.avatar),
        ),
        child: Icon(icon, color: tone, size: 21),
      ),
      title: Text(
        title,
        style: AppTheme.body(
          size: 15,
          weight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          subtitle,
          style: AppTheme.body(
            size: 12.5,
            weight: FontWeight.w500,
            color: AppColors.textTertiaryOn(context),
          ),
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

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.tile),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded,
              color: AppColors.warning, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Disclaimer: Reports are based on manually entered data and are '
              'for informational purposes only. Verify figures with your broker '
              'statements. Consult a qualified CA before filing taxes.',
              style: AppTheme.body(
                size: 11.5,
                weight: FontWeight.w500,
                color: AppColors.textSecondaryOn(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
