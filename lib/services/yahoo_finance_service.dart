import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/utils/platform_config.dart';
import '../core/utils/retry_helper.dart';
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
///
/// On web, requests are routed through a local proxy at /proxy?url=...
/// to bypass browser CORS restrictions.
///
/// Stability note: `query1.finance.yahoo.com` is an unofficial endpoint —
/// Yahoo has broken it without notice before. On failure, this service
/// automatically retries against `query2.finance.yahoo.com` as a fallback.
class YahooFinanceService implements PriceService {
  static const String _primaryHost =
      'https://query1.finance.yahoo.com/v8/finance/chart';
  static const String _fallbackHost =
      'https://query2.finance.yahoo.com/v8/finance/chart';

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

    // Retry with exponential backoff; also fall back to the secondary host
    // if the primary returns a non-200 or a hard error.
    return RetryHelper.withRetry(
      maxAttempts: 3,
      initialDelay: const Duration(seconds: 1),
      action: () => _fetchFromHost(_primaryHost, symbol),
      isFailure: (r) => !r.success,
      isRetriable: (r) {
        // Don't retry on "symbol not found" — that won't change on retry.
        final msg = r.error ?? '';
        return !msg.contains('not found') &&
            !msg.contains('Symbol is empty') &&
            !msg.contains('Invalid price');
      },
    ).then((primary) async {
      // If primary failed, try the fallback host once
      if (!primary.success) {
        final fallback = await _fetchFromHost(_fallbackHost, symbol);
        return fallback.success ? fallback : primary;
      }
      return primary;
    });
  }

  Future<PriceResult> _fetchFromHost(String baseUrl, String symbol) async {
    final url = PlatformConfig.buildUrl('$baseUrl/$symbol?interval=1d&range=1d');

    try {
      final response = await _client.get(
        url,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

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
