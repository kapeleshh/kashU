import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../core/utils/file_saver.dart';
import '../data/models/asset.dart';
import '../data/models/asset_type.dart';
import '../data/models/transaction.dart';
import '../data/models/transaction_type.dart';
import 'base_currency_converter.dart';

/// Handles CSV and PDF export of portfolio data for tax filing.
abstract final class ExportService {
  // ─── CSV ──────────────────────────────────────────────────────────────────

  /// The holdings still held. A fully sold holding stays stored at quantity
  /// 0 because the capital-gains report needs its cost basis, but it is
  /// closed, so it is left out of every holdings listing.
  static List<Asset> openHoldings(Iterable<Asset> assets) =>
      assets.where((a) => a.quantity > 0).toList();

  /// Build the holdings CSV rows (header + one row per open holding, see
  /// [openHoldings]). Pure — no I/O, so it's unit-testable independently of
  /// the share sheet.
  /// Prices are today's: a deposit valued from its terms shows its value
  /// and (for an RD) the instalments paid so far, not the figures stored
  /// the day it was added, so price × quantity matches the value columns.
  static List<List<dynamic>> holdingsCsvRows(List<Asset> assets) => [
        [
          'Name', 'Symbol', 'Type', 'Platform', 'Currency',
          'Quantity', 'Avg Buy Price', 'Current Price',
          'Invested', 'Current Value', 'Gain/Loss', 'Gain/Loss %',
          'Purchase Date',
        ],
        for (final a in openHoldings(assets))
          [
            a.name,
            a.symbol ?? '',
            a.type.displayName,
            a.platform ?? '',
            a.currency,
            _fmt(a.quantity),
            _fmt(a.investedPriceOn(DateTime.now())),
            _fmt(a.effectiveCurrentPrice),
            _fmt(a.totalInvested),
            _fmt(a.currentValue),
            _fmt(a.gainLoss),
            '${a.gainLossPercentage.toStringAsFixed(2)}%',
            _date(a.purchaseDate),
          ],
      ];

  /// Build the transactions CSV rows (header + one row per transaction). Pure.
  static List<List<dynamic>> transactionsCsvRows(
    List<Transaction> transactions,
    Map<String, String> assetNames,
  ) =>
      [
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

  /// Export all holdings as a CSV file and trigger the share sheet.
  static Future<void> exportHoldingsCsv(List<Asset> assets) async {
    final csv = const ListToCsvConverter().convert(holdingsCsvRows(assets));
    await _shareText(csv, 'kashu_holdings', 'csv', 'KashU Holdings');
  }

  /// Export all transactions as a CSV file and trigger the share sheet.
  static Future<void> exportTransactionsCsv(
    List<Transaction> transactions,
    Map<String, String> assetNames,
  ) async {
    final csv = const ListToCsvConverter()
        .convert(transactionsCsvRows(transactions, assetNames));
    await _shareText(csv, 'kashu_transactions', 'csv', 'KashU Transactions');
  }

  // ─── PDF ──────────────────────────────────────────────────────────────────

  /// Generate and share a PDF capital-gains summary suitable for a CA.
  ///
  /// Every total is in [fx]'s base currency; holding, sale and transaction
  /// rows stay in their own currency, which each table names in a column.
  static Future<void> exportCapitalGainsPdf(
    List<Asset> assets,
    List<Transaction> transactions,
    Map<String, String> assetNames,
    BaseCurrencyConverter fx,
  ) async {
    final now = DateTime.now();
    final doc = buildCapitalGainsPdf(assets, transactions, assetNames, fx,
        generatedAt: now);
    await saveAndShare(
      bytes: await doc.save(),
      filename: 'kashu_tax_report_${now.year}.pdf',
      mimeType: 'application/pdf',
      subject: 'KashU Tax Report ${now.year}',
    );
  }

  /// Preview PDF using the system print/preview dialog.
  static Future<void> previewCapitalGainsPdf(
    List<Asset> assets,
    List<Transaction> transactions,
    Map<String, String> assetNames,
    BaseCurrencyConverter fx,
  ) async {
    final doc = buildCapitalGainsPdf(assets, transactions, assetNames, fx);
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  /// Lay out the capital-gains report. No I/O, so it can be built in tests.
  static pw.Document buildCapitalGainsPdf(
    List<Asset> assets,
    List<Transaction> transactions,
    Map<String, String> assetNames,
    BaseCurrencyConverter fx, {
    DateTime? generatedAt,
  }) {
    final doc = pw.Document();
    final now = generatedAt ?? DateTime.now();
    // Sold-out holdings still supply the cost basis of their sales...
    final gains = computeCapitalGains(assets, transactions, assetNames);
    // ...but are no longer holdings (their value and cost are 0 anyway).
    final open = openHoldings(assets);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (_) => _pdfHeader(fx.base, now),
        footer: (ctx) => _pdfFooter(ctx),
        build: (ctx) => [
          _pdfPortfolioSummary(open, gains, fx),
          pw.SizedBox(height: 20),
          _pdfHoldingsTable(open),
          pw.SizedBox(height: 20),
          _pdfCapitalGainsTable(gains, fx),
          pw.SizedBox(height: 20),
          _pdfTransactionsTable(transactions, assetNames),
          pw.SizedBox(height: 16),
          _pdfDisclaimer(),
        ],
      ),
    );
    return doc;
  }

  // ─── Totals (base currency) ───────────────────────────────────────────────

  /// The report's portfolio totals, converted into [fx]'s base currency the
  /// same way the dashboard converts them. Each holding is in its own
  /// currency, so adding the raw figures would count dollars as rupees.
  static ({double invested, double value, double gain, double gainPct})
      portfolioTotals(List<Asset> assets, BaseCurrencyConverter fx) {
    var invested = 0.0;
    var value = 0.0;
    for (final a in assets) {
      invested += fx.investedOf(a);
      value += fx.valueOf(a);
    }
    final gain = value - invested;
    return (
      invested: invested,
      value: value,
      gain: gain,
      gainPct: invested > 0 ? gain / invested * 100 : 0.0,
    );
  }

  /// Short- and long-term gains, each converted from its sale's currency
  /// into [fx]'s base currency before being added up.
  static ({double shortTerm, double longTerm}) capitalGainsTotals(
    List<CapitalGainRow> gains,
    BaseCurrencyConverter fx,
  ) {
    var shortTerm = 0.0;
    var longTerm = 0.0;
    for (final g in gains) {
      final gain = fx.convert(g.gain, g.currency);
      if (g.isLongTerm) {
        longTerm += gain;
      } else {
        shortTerm += gain;
      }
    }
    return (shortTerm: shortTerm, longTerm: longTerm);
  }

  // ─── Capital gains calculation ────────────────────────────────────────────

  static List<CapitalGainRow> computeCapitalGains(
    List<Asset> assets,
    List<Transaction> transactions,
    Map<String, String> assetNames,
  ) {
    final rows = <CapitalGainRow>[];
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

      rows.add(CapitalGainRow(
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
                'Generated: ${_date(now)} | Base currency: $currency',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
          ],
        ),
        pw.Divider(),
      ],
    );
  }

  // PDF text uses the pdf package's built-in Helvetica, which has no
  // glyph for characters like an em dash, ≥ or ⚠ (they print as
  // nothing). Keep report strings plain ASCII; currencies are written as
  // codes (INR, USD) for the same reason.
  static pw.Widget _pdfFooter(pw.Context ctx) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('KashU - Privacy-first Portfolio Tracker',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
        pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
      ],
    );
  }

  static pw.Widget _pdfPortfolioSummary(
    List<Asset> assets,
    List<CapitalGainRow> gains,
    BaseCurrencyConverter fx,
  ) {
    final currency = fx.base;
    final totals = portfolioTotals(assets, fx);
    final converted = assets.any((a) => fx.currencyOf(a) != currency) ||
        gains.any((g) => g.currency.isNotEmpty && g.currency != currency);
    final rates = fx.rates;
    final rateSource = rates == null || !rates.success
        ? 'approximate offline exchange rates'
        : 'exchange rates of ${_date(rates.fetchedAt)}';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _summaryCell(
                  'Total Invested', '$currency ${_fmt(totals.invested)}'),
              _summaryCell('Current Value', '$currency ${_fmt(totals.value)}'),
              _summaryCell(
                  'Gain / Loss',
                  '${totals.gain >= 0 ? '+' : ''}$currency '
                      '${_fmt(totals.gain)} '
                      '(${totals.gainPct.toStringAsFixed(2)}%)'),
              _summaryCell('Holdings', '${assets.length}'),
            ],
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          converted
              ? 'All totals are in $currency. Amounts in other currencies '
                  'are converted at $rateSource; the tables below list each '
                  'row in its own currency.'
              : 'All amounts are in $currency.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ],
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

  /// The PDF's holdings rows: one per open holding (see [openHoldings]), in
  /// the holding's own currency. Pure, for tests.
  static List<List<String>> pdfHoldingsRows(List<Asset> assets) => [
        for (final a in openHoldings(assets))
          [
            a.name,
            a.type.displayName,
            a.currency,
            _fmt(a.quantity),
            _fmt(a.investedPriceOn(DateTime.now())),
            _fmt(a.effectiveCurrentPrice),
            _fmt(a.totalInvested),
            _fmt(a.currentValue),
            '${a.gainLoss >= 0 ? '+' : ''}${_fmt(a.gainLoss)} '
                '(${a.gainLossPercentage.toStringAsFixed(1)}%)',
          ],
      ];

  static pw.Widget _pdfHoldingsTable(List<Asset> assets) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Holdings',
            style: pw.TextStyle(
                fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        if (assets.isEmpty)
          pw.Text('No open holdings.',
              style:
                  const pw.TextStyle(fontSize: 9, color: PdfColors.grey500))
        else
          pw.TableHelper.fromTextArray(
            headers: [
              'Asset', 'Type', 'Cur.', 'Qty', 'Buy Price',
              'Current', 'Invested', 'Value', 'Gain/Loss',
            ],
            data: pdfHoldingsRows(assets),
            headerStyle:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.center,
              2: pw.Alignment.center,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
              6: pw.Alignment.centerRight,
              7: pw.Alignment.centerRight,
              8: pw.Alignment.centerRight,
            },
          ),
      ],
    );
  }

  static pw.Widget _pdfCapitalGainsTable(
      List<CapitalGainRow> gains, BaseCurrencyConverter fx) {
    final currency = fx.base;
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

    final totals = capitalGainsTotals(gains, fx);

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
                'STCG (held < 1 year): $currency ${_fmt(totals.shortTerm)}  |  '
                'LTCG (held 1 year or more): $currency ${_fmt(totals.longTerm)}  '
                '(totals in $currency)',
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey700)),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: [
            'Asset', 'Type', 'Sale Date', 'Cur.', 'Qty',
            'Avg Cost', 'Sale Price', 'Cost Basis',
            'Proceeds', 'Gain/Loss', 'Term',
          ],
          data: gains
              .map((g) => [
                    g.assetName,
                    g.assetType.displayName,
                    _date(g.saleDate),
                    g.currency,
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
          headers: [
            'Date', 'Asset', 'Type', 'Qty', 'Price', 'Amount', 'Cur.', 'Notes',
          ],
          data: sorted
              .map((t) => [
                    _date(t.date),
                    assetNames[t.assetId] ?? t.assetId,
                    t.type.displayName,
                    _fmt(t.quantity),
                    _fmt(t.price),
                    _fmt(t.amount),
                    t.currency,
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
        'Disclaimer: This report is generated from manually entered data '
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
    final ts = DateTime.now().millisecondsSinceEpoch;
    await saveAndShare(
      bytes: Uint8List.fromList(utf8.encode(content)),
      filename: '${baseName}_$ts.$ext',
      mimeType: ext == 'csv' ? 'text/csv' : 'text/plain',
      subject: subject,
    );
  }
}

// ─── Internal data class ───────────────────────────────────────────────────

class CapitalGainRow {
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

  const CapitalGainRow({
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
