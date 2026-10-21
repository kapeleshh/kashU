import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/utils/platform_config.dart';

/// A single stock/ETF/fund result from the Yahoo Finance search API.
class StockSearchResult {
  /// Yahoo Finance ticker symbol (e.g. RELIANCE.NS, AAPL, TCS.NS)
  final String symbol;

  /// Human-readable company/fund name (e.g. "RELIANCE INDUSTRIES LTD")
  final String name;

  /// Exchange code (e.g. NSI = NSE India, BSE = Bombay SE, NYQ = NYSE)
  final String exchange;

  /// Friendly exchange label shown to the user
  final String exchangeLabel;

  /// Asset type (EQUITY, ETF, MUTUALFUND, etc.)
  final String quoteType;

  const StockSearchResult({
    required this.symbol,
    required this.name,
    required this.exchange,
    required this.exchangeLabel,
    required this.quoteType,
  });

  /// Display label: "RELIANCE.NS — Reliance Industries Ltd (NSE)"
  String get displayLabel => '$symbol — $name ($exchangeLabel)';

  /// Short label for chips/tags: "NSE" / "BSE" / "NASDAQ"
  String get shortExchangeLabel => exchangeLabel;

  @override
  String toString() => displayLabel;

  /// Map Yahoo exchange codes to friendly names
  static String _exchangeLabel(String exchange) {
    const map = {
      'NSI': 'NSE',
      'BSE': 'BSE',
      'NYQ': 'NYSE',
      'NMS': 'NASDAQ',
      'NGM': 'NASDAQ',
      'NCM': 'NASDAQ',
      'ASE': 'AMEX',
      'LSE': 'LSE',
      'TOR': 'TSX',
      'AMS': 'AEX',
      'PAR': 'Euronext',
      'FRA': 'Frankfurt',
      'HKG': 'HKEX',
      'SHH': 'Shanghai',
      'SHZ': 'Shenzhen',
      'TYO': 'Tokyo',
      'BOM': 'BSE',
    };
    return map[exchange] ?? exchange;
  }

  factory StockSearchResult.fromJson(Map<String, dynamic> json) {
    final exchange = json['exchange'] as String? ?? '';
    return StockSearchResult(
      symbol: json['symbol'] as String? ?? '',
      name: (json['shortname'] as String?) ??
          (json['longname'] as String?) ??
          json['symbol'] as String? ??
          '',
      exchange: exchange,
      exchangeLabel: _exchangeLabel(exchange),
      quoteType: json['quoteType'] as String? ?? 'EQUITY',
    );
  }
}

/// Searches for stocks, ETFs, and mutual funds using the Yahoo Finance
/// search API. Results include symbol, name, and exchange.
///
/// On web, requests are routed through the same-origin CORS proxy.
class StockSearchService {
  static const String _searchUrl =
      'https://query1.finance.yahoo.com/v1/finance/search';

  final http.Client _client;

  StockSearchService({http.Client? client})
      : _client = client ?? http.Client();

  /// Search for stocks/ETFs/funds matching [query].
  ///
  /// Returns up to [maxResults] results filtered to equity-type instruments.
  /// Returns an empty list on error (never throws).
  Future<List<StockSearchResult>> search(
    String query, {
    int maxResults = 8,
  }) async {
    if (query.trim().length < 2) return [];

    final directUrl = Uri.parse(_searchUrl).replace(queryParameters: {
      'q': query.trim(),
      'quotesCount': maxResults.toString(),
      'newsCount': '0',
      'enableFuzzyQuery': 'false',
      'enableCb': 'false',
    }).toString();

    final url = PlatformConfig.buildUrl(directUrl);

    try {
      final response = await _client.get(
        url,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final quotes = data['quotes'] as List<dynamic>? ?? [];

      return quotes
          .whereType<Map<String, dynamic>>()
          .where((q) {
            final type = q['quoteType'] as String? ?? '';
            // Include equities, ETFs, and mutual funds
            return type == 'EQUITY' ||
                type == 'ETF' ||
                type == 'MUTUALFUND' ||
                type == 'INDEX';
          })
          .map(StockSearchResult.fromJson)
          .where((r) => r.symbol.isNotEmpty && r.name.isNotEmpty)
          .take(maxResults)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
