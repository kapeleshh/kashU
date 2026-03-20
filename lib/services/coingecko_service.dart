import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import '../data/models/asset_type.dart';
import 'price_service.dart';

/// A single cryptocurrency result from the CoinGecko search API.
class CryptoSearchResult {
  /// CoinGecko coin ID (used as the asset symbol, e.g. "bitcoin", "ethereum")
  final String id;

  /// Human-readable coin name (e.g. "Bitcoin", "Ethereum")
  final String name;

  /// Ticker symbol (e.g. "BTC", "ETH", "SOL")
  final String symbol;

  /// Market cap rank (1 = largest). Null if unranked.
  final int? marketCapRank;

  /// Small thumbnail image URL (optional)
  final String? thumb;

  const CryptoSearchResult({
    required this.id,
    required this.name,
    required this.symbol,
    this.marketCapRank,
    this.thumb,
  });

  factory CryptoSearchResult.fromJson(Map<String, dynamic> json) {
    return CryptoSearchResult(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      symbol: (json['symbol'] as String? ?? '').toUpperCase(),
      marketCapRank: json['market_cap_rank'] as int?,
      thumb: json['thumb'] as String?,
    );
  }

  /// Display label: "Bitcoin (BTC) — #1"
  String get displayLabel {
    final rank = marketCapRank != null ? ' — #$marketCapRank' : '';
    return '$name ($symbol)$rank';
  }
}

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

  /// Local proxy base URL (used on web to bypass CORS)
  static const String _proxyBase = 'http://localhost:8080/proxy?url=';

  final http.Client _client;

  /// Default vs_currency for price (can be overridden)
  final String vsCurrency;

  CoinGeckoService({
    http.Client? client,
    this.vsCurrency = 'usd',
  }) : _client = client ?? http.Client();

  /// Build the request URL — uses proxy on web, direct on mobile/desktop
  Uri _buildUrl(String directUrl) {
    if (kIsWeb) {
      return Uri.parse('$_proxyBase${Uri.encodeComponent(directUrl)}');
    }
    return Uri.parse(directUrl);
  }

  @override
  bool supportsAssetType(AssetType type) => type == AssetType.crypto;

  /// Search for cryptocurrencies by name or symbol.
  ///
  /// Returns results sorted by market cap rank (most popular first).
  /// Returns empty list on error (never throws).
  Future<List<CryptoSearchResult>> search(
    String query, {
    int maxResults = 10,
  }) async {
    if (query.trim().isEmpty) return [];

    final directUrl =
        '$_baseUrl/search?query=${Uri.encodeComponent(query.trim())}';
    final url = _buildUrl(directUrl);

    try {
      final response = await _client.get(
        url,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final coins = data['coins'] as List<dynamic>? ?? [];

      return coins
          .whereType<Map<String, dynamic>>()
          .map(CryptoSearchResult.fromJson)
          .where((r) => r.id.isNotEmpty && r.name.isNotEmpty)
          // Sort by market cap rank (ranked coins first, then unranked)
          .toList()
        ..sort((a, b) {
          if (a.marketCapRank == null && b.marketCapRank == null) return 0;
          if (a.marketCapRank == null) return 1;
          if (b.marketCapRank == null) return -1;
          return a.marketCapRank!.compareTo(b.marketCapRank!);
        })
        ..take(maxResults);
    } catch (_) {
      return [];
    }
  }

  @override
  Future<PriceResult> fetchPrice(String symbol) async {
    final coinId = symbol.trim().toLowerCase();

    if (coinId.isEmpty) {
      return PriceResult.failure(symbol, 'Symbol is empty');
    }

    final directUrl =
        '$_baseUrl/simple/price?ids=$coinId&vs_currencies=$vsCurrency';
    final url = _buildUrl(directUrl);

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
    final directUrl =
        '$_baseUrl/simple/price?ids=$ids&vs_currencies=$vsCurrency';
    final url = _buildUrl(directUrl);

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
