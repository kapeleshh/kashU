import 'package:http/http.dart' as http;
import '../core/utils/platform_config.dart';
import '../data/models/asset_type.dart';
import 'price_service.dart';

/// Secondary fallback price service using stooq.com's free CSV endpoint.
///
/// Used when Yahoo Finance is unreachable or rate-limited.
///
/// Symbol mapping from Yahoo → Stooq:
///   Yahoo: RELIANCE.NS   → Stooq: reliance.ns
///   Yahoo: AAPL          → Stooq: aapl.us
///   Yahoo: GC=F          → Stooq: gc.f (gold futures)
///   Yahoo: ^NSEI         → Stooq: ^nsei
///
/// Limitations:
///   - Some Indian penny stocks and very small caps may be absent.
///   - Stooq does not provide intraday prices; it returns the last daily close.
///   - Currency is inferred (INR for .ns/.bo, USD otherwise).
class StooqService implements PriceService {
  static const String _baseUrl =
      'https://stooq.com/q/l/?f=sd2t2ohlcv&h&e=csv&s=';

  final http.Client _client;

  StooqService({http.Client? client}) : _client = client ?? http.Client();

  @override
  bool supportsAssetType(AssetType type) {
    switch (type) {
      case AssetType.stock:
      case AssetType.mutualFund:
      case AssetType.gold:
      case AssetType.bond:
        return true;
      default:
        return false;
    }
  }

  @override
  Future<PriceResult> fetchPrice(String symbol) async {
    final stooqSymbol = _toStooqSymbol(symbol);
    final url = PlatformConfig.buildUrl('$_baseUrl$stooqSymbol');

    try {
      final response = await _client.get(
        url,
        headers: {'User-Agent': 'Mozilla/5.0'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return PriceResult.failure(
            symbol, 'Stooq HTTP ${response.statusCode}');
      }

      final price = _parseCsvPrice(response.body);
      if (price == null || price <= 0) {
        return PriceResult.failure(symbol, 'Stooq: no valid price in response');
      }

      final currency = _inferCurrency(symbol);
      return PriceResult(
        symbol: symbol,
        price: price,
        currency: currency,
        fetchedAt: DateTime.now(),
        success: true,
      );
    } on http.ClientException catch (e) {
      return PriceResult.failure(symbol, 'Stooq network error: ${e.message}');
    } catch (e) {
      return PriceResult.failure(symbol, 'Stooq unexpected error: $e');
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Helpers
  // ───────────────────────────────────────────────────────────────────────────

  /// Convert Yahoo Finance symbol conventions to Stooq conventions.
  String _toStooqSymbol(String symbol) {
    // GC=F (COMEX gold) → gc.f
    // SI=F (silver) → si.f
    if (symbol.contains('=F')) {
      return symbol.replaceAll('=F', '.f').toLowerCase();
    }
    // Already has exchange suffix (.NS, .BO, .L, etc.) → just lowercase
    if (symbol.contains('.')) {
      return symbol.toLowerCase();
    }
    // Plain US ticker → append .us
    return '${symbol.toLowerCase()}.us';
  }

  /// Parse the "Close" column from Stooq's CSV response.
  ///
  /// CSV format (first two lines):
  ///   Symbol,Date,Time,Open,High,Low,Close,Volume
  ///   RELIANCE.NS,2024-01-15,15:30:00,2450.00,2480.00,2440.00,2465.50,1234567
  double? _parseCsvPrice(String body) {
    final lines = body.trim().split('\n');
    if (lines.length < 2) return null;

    final headers =
        lines[0].split(',').map((h) => h.trim().toLowerCase()).toList();
    final closeIdx = headers.indexOf('close');
    if (closeIdx < 0) return null;

    final data = lines[1].split(',');
    if (data.length <= closeIdx) return null;

    return double.tryParse(data[closeIdx].trim());
  }

  /// Infer the currency from the symbol suffix.
  String _inferCurrency(String symbol) {
    final upper = symbol.toUpperCase();
    if (upper.endsWith('.NS') || upper.endsWith('.BO')) return 'INR';
    if (upper.endsWith('.L')) return 'GBp'; // London pence
    if (upper.endsWith('.PA') || upper.endsWith('.DE')) return 'EUR';
    return 'USD';
  }
}
