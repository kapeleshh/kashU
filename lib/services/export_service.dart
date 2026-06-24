import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../data/models/asset.dart';
import '../data/models/asset_type.dart';
import '../data/models/transaction.dart';
import '../data/models/transaction_type.dart';

/// Handles CSV and PDF export of portfolio data for tax filing.
abstract final class ExportService {
  // ─── CSV ──────────────────────────────────────────────────────────────────

  /// Export all holdings as a CSV file and trigger the share sheet.
  static Future<void> exportHoldingsCsv(List<Asset> assets) async {
    final rows = <List<dynamic>>[
      // Header
      [
        'Name', 'Symbol', 'Type', 'Platform', 'Currency',
        'Quantity', 'Avg Buy Price', 'Current Price',
        'Invested', 'Current Value', 'Gain/Loss', 'Gain/Loss %',
        'Purchase Date',
      ],
      // Data
      for (final a in assets)
        [
          a.name,
          a.symbol ?? '',
          a.type.displayName,
          a.platform ?? '',
          a.currency,
          _fmt(a.quantity),
          _fmt(a.purchasePrice),
          _fmt(a.currentPrice),
          _fmt(a.totalInvested),
          _fmt(a.currentValue),
          _fmt(a.gainLoss),
          '${a.gainLossPercentage.toStringAsFixed(2)}%',
          _date(a.purchaseDate),
        ],
    ];

    final csv = const ListToCsvConverter().convert(rows);
    await _shareText(csv, 'kashu_holdings', 'csv', 'KashU Holdings');
  }

  /// Export all transactions as a CSV file and trigger the share sheet.
  static Future<void> exportTransactionsCsv(
    List<Transaction> transactions,
    Map<String, String> assetNames,
  ) async {
    final rows = <List<dynamic>>[
      ['Date', 'Asset', 'Type', 'Quantity', 'Price', 'Amount', 'Currency', 'Notes'],
      for (final t in transactions)
        [
          _date(t.date),
          assetNames[t.assetId] ?? t.assetId,
          t.type.displayName,
          _fmt(t.quantity),
          _fmt(t.price),
          _fmt(t.amount),
          t.currency,
          t.notes ?? '',
        ],
    ];

    final csv = const ListToCsvConverter().convert(rows);
    await _shareText(csv, 'kashu_transactions', 'csv', 'KashU Transactions');
  }

  // ─── PDF ──────────────────────────────────────────────────────────────────

  /// Generate and share a PDF capital-gains summary suitable for a CA.
  static Future<void> exportCapitalGainsPdf(
    List<Asset> assets,
    List<Transaction> transactions,
    Map<String, String> assetNames,
    String baseCurrency,
  ) async {
    final doc = pw.Document();
    final now = DateTime.now();

    // Compute capital gains: sell transactions where buy data is available
    final gains = _computeCapitalGains(assets, transactions, assetNames);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (_) => _pdfHeader(baseCurrency, now),
        footer: (ctx) => _pdfFooter(ctx),
        build: (ctx) => [
          _pdfPortfolioSummary(assets, baseCurrency),
          pw.SizedBox(height: 20),
          _pdfHoldingsTable(assets, baseCurrency),
          pw.SizedBox(height: 20),
          _pdfCapitalGainsTable(gains, baseCurrency),
          pw.SizedBox(height: 20),
          _pdfTransactionsTable(transactions, assetNames, baseCurrency),
          pw.SizedBox(height: 16),
          _pdfDisclaimer(),
        ],
      ),
    );

    final bytes = await doc.save();
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
        '${dir.path}/kashu_tax_report_${now.year}.pdf');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'KashU Tax Report ${now.year}',
    );
  }

  /// Preview PDF using the system print/preview dialog.
  static Future<void> previewCapitalGainsPdf(
    List<Asset> assets,
    List<Transaction> transactions,
    Map<String, String> assetNames,
    String baseCurrency,
  ) async {
    final doc = pw.Document();
    final now = DateTime.now();
    final gains = _computeCapitalGains(assets, transactions, assetNames);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (_) => _pdfHeader(baseCurrency, now),
        footer: (ctx) => _pdfFooter(ctx),
        build: (ctx) => [
          _pdfPortfolioSummary(assets, baseCurrency),
          pw.SizedBox(height: 20),
          _pdfHoldingsTable(assets, baseCurrency),
          pw.SizedBox(height: 20),
          _pdfCapitalGainsTable(gains, baseCurrency),
          pw.SizedBox(height: 20),
          _pdfTransactionsTable(transactions, assetNames, baseCurrency),
          pw.SizedBox(height: 16),
          _pdfDisclaimer(),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  // ─── Capital gains calculation ────────────────────────────────────────────

  static List<_CapitalGainRow> _computeCapitalGains(
    List<Asset> assets,
    List<Transaction> transactions,
    Map<String, String> assetNames,
  ) {
    final rows = <_CapitalGainRow>[];
    final assetMap = {for (final a in assets) a.id: a};

    final sells = transactions
        .where((t) => t.type == TransactionType.sell)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    for (final sell in sells) {
      final asset = assetMap[sell.assetId];
      if (asset == null) continue;

      // Use average purchase price as cost basis
      final costBasis = sell.quantity * asset.purchasePrice;
      final saleProceeds = sell.amount;
      final gain = saleProceeds - costBasis;

      // STCG vs LTCG: 12 months threshold (simplified)
      final holdingDays =
          sell.date.difference(asset.purchaseDate).inDays;
      final isLongTerm = holdingDays >= 365;

      rows.add(_CapitalGainRow(
        assetName: assetNames[sell.assetId] ?? 'Unknown',
        assetType: asset.type,
        saleDate: sell.date,
        quantity: sell.quantity,
        avgCostBasis: asset.purchasePrice,
        salePrice: sell.price,
        costBasis: costBasis,
        saleProceeds: saleProceeds,
        gain: gain,
        isLongTerm: isLongTerm,
        holdingDays: holdingDays,
        currency: sell.currency,
      ));
    }

    return rows;
  }

  // ─── PDF building blocks ──────────────────────────────────────────────────

  static pw.Widget _pdfHeader(String currency, DateTime now) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('KashU Portfolio Report',
                style: pw.TextStyle(
                    fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text(
                'Generated: ${_date(now)} | Currency: $currency',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
          ],
        ),
        pw.Divider(),
      ],
    );
  }

  static pw.Widget _pdfFooter(pw.Context ctx) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('KashU — Privacy-first Portfolio Tracker',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
        pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
      ],
    );
  }

  static pw.Widget _pdfPortfolioSummary(
      List<Asset> assets, String currency) {
    final totalInvested =
        assets.fold(0.0, (s, a) => s + a.totalInvested);
    final totalValue = assets.fold(0.0, (s, a) => s + a.currentValue);
    final totalGain = totalValue - totalInvested;
    final gainPct =
        totalInvested > 0 ? (totalGain / totalInvested) * 100 : 0.0;

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _summaryCell('Total Invested', '$currency ${_fmt(totalInvested)}'),
          _summaryCell('Current Value', '$currency ${_fmt(totalValue)}'),
          _summaryCell(
              'Gain / Loss',
              '${totalGain >= 0 ? '+' : ''}$currency ${_fmt(totalGain)} '
                  '(${gainPct.toStringAsFixed(2)}%)'),
          _summaryCell('Holdings', '${assets.length}'),
        ],
      ),
    );
  }

  static pw.Widget _summaryCell(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(label,
            style:
                const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
        pw.SizedBox(height: 4),
        pw.Text(value,
            style: pw.TextStyle(
                fontSize: 11, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  static pw.Widget _pdfHoldingsTable(
      List<Asset> assets, String currency) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Holdings',
            style: pw.TextStyle(
                fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: [
            'Asset', 'Type', 'Qty', 'Buy Price',
            'Current', 'Invested', 'Value', 'Gain/Loss',
          ],
          data: assets
              .map((a) => [
                    a.name,
                    a.type.displayName,
                    _fmt(a.quantity),
                    _fmt(a.purchasePrice),
                    _fmt(a.currentPrice),
                    _fmt(a.totalInvested),
                    _fmt(a.currentValue),
                    '${a.gainLoss >= 0 ? '+' : ''}${_fmt(a.gainLoss)} '
                        '(${a.gainLossPercentage.toStringAsFixed(1)}%)',
                  ])
              .toList(),
          headerStyle:
              pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
          cellStyle: const pw.TextStyle(fontSize: 8),
          headerDecoration:
              const pw.BoxDecoration(color: PdfColors.grey200),
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.center,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
            5: pw.Alignment.centerRight,
            6: pw.Alignment.centerRight,
            7: pw.Alignment.centerRight,
          },
        ),
      ],
    );
  }

  static pw.Widget _pdfCapitalGainsTable(
      List<_CapitalGainRow> gains, String currency) {
    if (gains.isEmpty) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Capital Gains',
              style: pw.TextStyle(
                  fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text('No sell transactions recorded.',
              style:
                  const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
        ],
      );
    }

    final stcg = gains.where((g) => !g.isLongTerm);
    final ltcg = gains.where((g) => g.isLongTerm);
    final totalStcg = stcg.fold(0.0, (s, g) => s + g.gain);
    final totalLtcg = ltcg.fold(0.0, (s, g) => s + g.gain);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Capital Gains Summary',
            style: pw.TextStyle(
                fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Row(
          children: [
            pw.Text(
                'STCG (held < 1 year): $currency ${_fmt(totalStcg)}  |  '
                'LTCG (held ≥ 1 year): $currency ${_fmt(totalLtcg)}',
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey700)),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: [
            'Asset', 'Type', 'Sale Date', 'Qty',
            'Avg Cost', 'Sale Price', 'Cost Basis',
            'Proceeds', 'Gain/Loss', 'Term',
          ],
          data: gains
              .map((g) => [
                    g.assetName,
                    g.assetType.displayName,
                    _date(g.saleDate),
                    _fmt(g.quantity),
                    _fmt(g.avgCostBasis),
                    _fmt(g.salePrice),
                    _fmt(g.costBasis),
                    _fmt(g.saleProceeds),
                    '${g.gain >= 0 ? '+' : ''}${_fmt(g.gain)}',
                    g.isLongTerm ? 'LTCG' : 'STCG',
                  ])
              .toList(),
          headerStyle:
              pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
          cellStyle: const pw.TextStyle(fontSize: 8),
          headerDecoration:
              const pw.BoxDecoration(color: PdfColors.grey200),
        ),
      ],
    );
  }

  static pw.Widget _pdfTransactionsTable(
    List<Transaction> transactions,
    Map<String, String> assetNames,
    String currency,
  ) {
    final sorted = [...transactions]
      ..sort((a, b) => b.date.compareTo(a.date));

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('All Transactions',
            style: pw.TextStyle(
                fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: ['Date', 'Asset', 'Type', 'Qty', 'Price', 'Amount', 'Notes'],
          data: sorted
              .map((t) => [
                    _date(t.date),
                    assetNames[t.assetId] ?? t.assetId,
                    t.type.displayName,
                    _fmt(t.quantity),
                    _fmt(t.price),
                    _fmt(t.amount),
                    t.notes ?? '',
                  ])
              .toList(),
          headerStyle:
              pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
          cellStyle: const pw.TextStyle(fontSize: 8),
          headerDecoration:
              const pw.BoxDecoration(color: PdfColors.grey200),
        ),
      ],
    );
  }

  static pw.Widget _pdfDisclaimer() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Text(
        '⚠ Disclaimer: This report is generated from manually entered data '
        'and is provided for informational purposes only. It does not '
        'constitute financial or tax advice. Please verify all figures with '
        'your broker statements and consult a qualified CA/tax advisor before filing.',
        style:
            const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  static String _fmt(double v) => v.toStringAsFixed(2);

  static String _date(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';

  static Future<void> _shareText(
    String content,
    String baseName,
    String ext,
    String subject,
  ) async {
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/${baseName}_$ts.$ext');
    await file.writeAsString(content);
    await Share.shareXFiles([XFile(file.path)], subject: subject);
  }
}

// ─── Internal data class ───────────────────────────────────────────────────

class _CapitalGainRow {
  final String assetName;
  final AssetType assetType;
  final DateTime saleDate;
  final double quantity;
  final double avgCostBasis;
  final double salePrice;
  final double costBasis;
  final double saleProceeds;
  final double gain;
  final bool isLongTerm;
  final int holdingDays;
  final String currency;

  const _CapitalGainRow({
    required this.assetName,
    required this.assetType,
    required this.saleDate,
    required this.quantity,
    required this.avgCostBasis,
    required this.salePrice,
    required this.costBasis,
    required this.saleProceeds,
    required this.gain,
    required this.isLongTerm,
    required this.holdingDays,
    required this.currency,
  });
}
