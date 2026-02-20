import 'dart:convert';
import 'package:http/http.dart' as http;
import '../data/models/asset_type.dart';
import 'price_service.dart';

/// Fetches cryptocurrency prices from the CoinGecko public API.
/// No API key required. Free tier: ~10-30 calls/minute.
///
/// Symbol format: lowercase coin ID as used by CoinGecko
///   - bitcoin, ethereum, solana, binancecoin
///   - ripple, cardano, polkadot, dogecoin
///
/// Find coin IDs at: https://api.coingecko.com/api/v3/coins/list
class CoinGeckoService implements PriceService {
  static const String _baseUrl = 'https://api.coingecko.com/api/v3';

  final http.Client _client;

  /// Default vs_currency for price (can be overridden)
  final String vsCurrency;

  CoinGeckoService({
    http.Client? client,
    this.vsCurrency = 'usd',
  }) : _client = client ?? http.Client();

  @override
  bool supportsAssetType(AssetType type) => type == AssetType.crypto;

  @override
  Future<PriceResult> fetchPrice(String symbol) async {
    final coinId = symbol.trim().toLowerCase();

    if (coinId.isEmpty) {
      return PriceResult.failure(symbol, 'Symbol is empty');
    }

    final url = Uri.parse(
      '$_baseUrl/simple/price?ids=$coinId&vs_currencies=$vsCurrency',
    );

    try {
      final response = await _client.get(
        url,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 429) {
        return PriceResult.failure(
          symbol,
          'Rate limit reached. Please wait a moment and try again.',
        );
      }

      if (response.statusCode != 200) {
        return PriceResult.failure(
          symbol,
          'HTTP ${response.statusCode}: CoinGecko API error',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (!data.containsKey(coinId)) {
        return PriceResult.failure(
          symbol,
          'Coin "$coinId" not found. Check spelling (e.g. "bitcoin", "ethereum")',
        );
      }

      final coinData = data[coinId] as Map<String, dynamic>;
      final price = (coinData[vsCurrency] as num?)?.toDouble();

      if (price == null || price <= 0) {
        return PriceResult.failure(symbol, 'Invalid price data for $coinId');
      }

      return PriceResult(
        symbol: symbol,
        price: price,
        currency: vsCurrency.toUpperCase(),
        fetchedAt: DateTime.now(),
        success: true,
      );
    } on http.ClientException catch (e) {
      return PriceResult.failure(symbol, 'Network error: ${e.message}');
    } catch (e) {
      return PriceResult.failure(symbol, 'Unexpected error: $e');
    }
  }

  /// Fetch prices for multiple coins in one API call (more efficient)
  Future<List<PriceResult>> fetchMultiplePrices(List<String> symbols) async {
    if (symbols.isEmpty) return [];

    final ids = symbols.map((s) => s.trim().toLowerCase()).join(',');
    final url = Uri.parse(
      '$_baseUrl/simple/price?ids=$ids&vs_currencies=$vsCurrency',
    );

    try {
      final response = await _client.get(
        url,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return symbols
            .map((s) => PriceResult.failure(
                  s,
                  'HTTP ${response.statusCode}: CoinGecko error',
                ))
            .toList();
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      return symbols.map((symbol) {
        final coinId = symbol.trim().toLowerCase();
        if (!data.containsKey(coinId)) {
          return PriceResult.failure(symbol, 'Coin "$coinId" not found');
        }
        final coinData = data[coinId] as Map<String, dynamic>;
        final price = (coinData[vsCurrency] as num?)?.toDouble();
        if (price == null || price <= 0) {
          return PriceResult.failure(symbol, 'Invalid price for $coinId');
        }
        return PriceResult(
          symbol: symbol,
          price: price,
          currency: vsCurrency.toUpperCase(),
          fetchedAt: DateTime.now(),
          success: true,
        );
      }).toList();
    } catch (e) {
      return symbols
          .map((s) => PriceResult.failure(s, 'Error: $e'))
          .toList();
    }
  }
}
