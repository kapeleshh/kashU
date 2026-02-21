import 'dart:convert';
import 'package:http/http.dart' as http;
import '../data/models/asset_type.dart';
import 'price_service.dart';

/// Fetches stock, ETF, mutual fund, and commodity (gold) prices
/// from the unofficial Yahoo Finance API.
///
/// Supported symbols:
///   - Indian NSE stocks:  RELIANCE.NS, TCS.NS, INFY.NS
///   - Indian BSE stocks:  RELIANCE.BO
///   - US stocks:          AAPL, GOOGL, MSFT
///   - Gold futures:       GC=F
///   - Silver futures:     SI=F
///   - NSE ETFs:           NIFTYBEES.NS, GOLDBEES.NS
class YahooFinanceService implements PriceService {
  static const String _baseUrl =
      'https://query1.finance.yahoo.com/v8/finance/chart';

  final http.Client _client;

  YahooFinanceService({http.Client? client})
      : _client = client ?? http.Client();

  @override
  bool supportsAssetType(AssetType type) {
    switch (type) {
      case AssetType.stock:
      case AssetType.mutualFund:
      case AssetType.gold:
      case AssetType.bond:
        return true;
      case AssetType.crypto:
      case AssetType.fixedDeposit:
      case AssetType.cash:
      case AssetType.realEstate:
        return false;
    }
  }

  @override
  Future<PriceResult> fetchPrice(String symbol) async {
    if (symbol.trim().isEmpty) {
      return PriceResult.failure(symbol, 'Symbol is empty');
    }

    final url = Uri.parse('$_baseUrl/$symbol?interval=1d&range=1d');

    try {
      final response = await _client.get(
        url,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return PriceResult.failure(
          symbol,
          'HTTP ${response.statusCode}: Symbol not found or unavailable',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final result = data['chart']?['result'];

      if (result == null || (result as List).isEmpty) {
        return PriceResult.failure(symbol, 'No data returned for $symbol');
      }

      final chartResult = result[0] as Map<String, dynamic>;
      final meta = chartResult['meta'] as Map<String, dynamic>?;

      if (meta == null) {
        return PriceResult.failure(symbol, 'Invalid response structure');
      }

      // Use regularMarketPrice (current/last close)
      final price = (meta['regularMarketPrice'] as num?)?.toDouble();
      final currency = meta['currency'] as String? ?? 'USD';

      if (price == null || price <= 0) {
        return PriceResult.failure(symbol, 'Invalid price data for $symbol');
      }

      return PriceResult(
        symbol: symbol,
        price: price,
        currency: currency,
        fetchedAt: DateTime.now(),
        success: true,
      );
    } on http.ClientException catch (e) {
      return PriceResult.failure(symbol, 'Network error: ${e.message}');
    } catch (e) {
      return PriceResult.failure(symbol, 'Unexpected error: $e');
    }
  }

  /// Convenience method: fetch gold price using COMEX international symbol
  Future<PriceResult> fetchGoldPrice() => fetchPrice(PriceSymbols.goldComex);
}
