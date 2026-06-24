import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
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
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Generating export…'),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _InfoCard(),
                const SizedBox(height: 24),
                _SectionHeader('CSV Exports'),
                const SizedBox(height: 8),
                _ExportTile(
                  icon: Icons.table_chart_outlined,
                  title: 'Holdings CSV',
                  subtitle: 'All current holdings with cost basis and P&L',
                  onTap: () => _export(_exportHoldings),
                ),
                const SizedBox(height: 8),
                _ExportTile(
                  icon: Icons.receipt_long_outlined,
                  title: 'Transactions CSV',
                  subtitle: 'Full transaction history — buy, sell, dividends',
                  onTap: () => _export(_exportTransactions),
                ),
                const SizedBox(height: 24),
                _SectionHeader('PDF Report'),
                const SizedBox(height: 8),
                _ExportTile(
                  icon: Icons.picture_as_pdf_outlined,
                  title: 'Capital Gains Report (PDF)',
                  subtitle:
                      'Holdings, capital gains summary (STCG/LTCG), and full transaction log. Share with your CA.',
                  onTap: () => _export(_exportPdf),
                ),
                const SizedBox(height: 8),
                _ExportTile(
                  icon: Icons.preview_outlined,
                  title: 'Preview PDF',
                  subtitle: 'Preview the report before exporting',
                  onTap: () => _export(_previewPdf),
                ),
                const SizedBox(height: 32),
                _Disclaimer(),
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

class _InfoCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: AppColors.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Generate CSV or PDF reports of your portfolio for tax filing. '
              'The capital gains report calculates STCG (< 1 year) and '
              'LTCG (≥ 1 year) based on your transaction history.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
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
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

class _ExportTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ExportTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.primary, size: 20),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
        ),
        trailing: Icon(Icons.chevron_right, color: AppColors.textTertiary),
        onTap: onTap,
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '⚠ Disclaimer: Reports are based on manually entered data and are '
        'for informational purposes only. Verify figures with your broker '
        'statements. Consult a qualified CA before filing taxes.',
        style: TextStyle(
          color: AppColors.textTertiary,
          fontSize: 11,
        ),
      ),
    );
  }
}
