import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/utils/platform_config.dart';
import '../core/utils/retry_helper.dart';
import '../data/models/asset_type.dart';
import 'price_service.dart';

/// Secondary crypto price source using CryptoCompare's free endpoints.
/// Used when CoinGecko is unreachable or rate-limited.
///
/// Why CryptoCompare: keyless at low volume, quotes natively in INR (and
/// every other supported currency), and `pricemulti` batches like
/// CoinGecko's `simple/price`.
///
/// Symbols: the app stores CoinGecko coin ids ("bitcoin", "ethereum"), so
/// this service maps them to CryptoCompare ticker symbols ("BTC", "ETH")
/// via [_idToTicker]. Unmapped ids return a failure and fall through to the
/// price cache.
///
/// Gotcha: CryptoCompare reports errors as HTTP 200 with a body of
/// `{"Response": "Error", "Message": ...}` — the body must be checked.
/// Like CoinGecko, requests are retried on network errors but NOT on 429.
class CryptoCompareService implements PriceService {
  static const String _baseUrl = 'https://min-api.cryptocompare.com/data';

  final http.Client _client;

  /// Quote currency (e.g. 'inr', 'usd').
  final String vsCurrency;

  CryptoCompareService({
    http.Client? client,
    this.vsCurrency = 'usd',
  }) : _client = client ?? http.Client();

  /// CoinGecko coin id → CryptoCompare ticker for the top coins by market
  /// cap. Coverage beyond this list isn't needed for a fallback — unmapped
  /// ids fail here and the caller falls back to the cache.
  static const Map<String, String> _idToTicker = {
    'bitcoin': 'BTC',
    'ethereum': 'ETH',
    'tether': 'USDT',
    'binancecoin': 'BNB',
    'solana': 'SOL',
    'usd-coin': 'USDC',
    'ripple': 'XRP',
    'staked-ether': 'STETH',
    'dogecoin': 'DOGE',
    'cardano': 'ADA',
    'tron': 'TRX',
    'avalanche-2': 'AVAX',
    'shiba-inu': 'SHIB',
    'wrapped-bitcoin': 'WBTC',
    'polkadot': 'DOT',
    'chainlink': 'LINK',
    'bitcoin-cash': 'BCH',
    'near': 'NEAR',
    'matic-network': 'MATIC',
    'polygon-ecosystem-token': 'POL',
    'litecoin': 'LTC',
    'internet-computer': 'ICP',
    'uniswap': 'UNI',
    'dai': 'DAI',
    'ethereum-classic': 'ETC',
    'aptos': 'APT',
    'stellar': 'XLM',
    'monero': 'XMR',
    'okb': 'OKB',
    'filecoin': 'FIL',
    'cosmos': 'ATOM',
    'hedera-hashgraph': 'HBAR',
    'crypto-com-chain': 'CRO',
    'arbitrum': 'ARB',
    'optimism': 'OP',
    'vechain': 'VET',
    'maker': 'MKR',
    'sui': 'SUI',
    'the-graph': 'GRT',
    'injective-protocol': 'INJ',
    'render-token': 'RENDER',
    'algorand': 'ALGO',
    'aave': 'AAVE',
    'quant-network': 'QNT',
    'fantom': 'FTM',
    'thorchain': 'RUNE',
    'the-sandbox': 'SAND',
    'decentraland': 'MANA',
    'tezos': 'XTZ',
    'eos': 'EOS',
    'pepe': 'PEPE',
  };

  /// Resolve a CoinGecko id (or raw ticker) to a CryptoCompare ticker.
  /// Returns null when the id is unknown.
  static String? tickerForId(String coinGeckoId) {
    final id = coinGeckoId.trim().toLowerCase();
    return _idToTicker[id];
  }

  @override
  bool supportsAssetType(AssetType type) => type == AssetType.crypto;

  @override
  Future<PriceResult> fetchPrice(String symbol) async {
    final ticker = tickerForId(symbol);
    if (ticker == null) {
      return PriceResult.failure(
        symbol,
        'No CryptoCompare mapping for "$symbol"',
      );
    }

    return RetryHelper.withRetry(
      maxAttempts: 3,
      initialDelay: const Duration(seconds: 2),
      action: () => _fetchSingle(ticker, symbol),
      isFailure: (r) => !r.success,
      // Don't retry on rate limit — it will not help immediately
      isRetriable: (r) => !(r.error?.contains('Rate limit') ?? false),
    );
  }

  Future<PriceResult> _fetchSingle(String ticker, String originalSymbol) async {
    final tsym = vsCurrency.toUpperCase();
    final url = PlatformConfig.buildUrl(
        '$_baseUrl/price?fsym=$ticker&tsyms=$tsym');

    try {
      final response = await _client.get(
        url,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 429) {
        return PriceResult.failure(
          originalSymbol,
          'Rate limit reached. Please wait a moment and try again.',
        );
      }
      if (response.statusCode != 200) {
        return PriceResult.failure(
          originalSymbol,
          'HTTP ${response.statusCode}: CryptoCompare API error',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      // CryptoCompare signals errors with HTTP 200 + Response: "Error"
      if (data['Response'] == 'Error') {
        return PriceResult.failure(
          originalSymbol,
          'CryptoCompare: ${data['Message'] ?? 'unknown error'}',
        );
      }

      final price = (data[tsym] as num?)?.toDouble();
      if (price == null || price <= 0) {
        return PriceResult.failure(
            originalSymbol, 'Invalid price data for $ticker');
      }

      return PriceResult(
        symbol: originalSymbol,
        price: price,
        currency: tsym,
        fetchedAt: DateTime.now(),
        success: true,
      );
    } on http.ClientException catch (e) {
      return PriceResult.failure(originalSymbol, 'Network error: ${e.message}');
    } catch (e) {
      return PriceResult.failure(originalSymbol, 'Unexpected error: $e');
    }
  }

  /// Fetch prices for multiple CoinGecko ids in one API call.
  /// Results are returned in the same order as [symbols].
  Future<List<PriceResult>> fetchMultiplePrices(List<String> symbols) async {
    if (symbols.isEmpty) return [];

    final tsym = vsCurrency.toUpperCase();
    final tickers = <String, String>{}; // id → ticker (mapped subset)
    for (final s in symbols) {
      final t = tickerForId(s);
      if (t != null) tickers[s] = t;
    }

    if (tickers.isEmpty) {
      return symbols
          .map((s) =>
              PriceResult.failure(s, 'No CryptoCompare mapping for "$s"'))
          .toList();
    }

    final url = PlatformConfig.buildUrl(
        '$_baseUrl/pricemulti?fsyms=${tickers.values.join(',')}&tsyms=$tsym');

    try {
      final response = await _client.get(
        url,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return symbols
            .map((s) => PriceResult.failure(
                s, 'HTTP ${response.statusCode}: CryptoCompare error'))
            .toList();
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (data['Response'] == 'Error') {
        final message = 'CryptoCompare: ${data['Message'] ?? 'unknown error'}';
        return symbols.map((s) => PriceResult.failure(s, message)).toList();
      }

      return symbols.map((symbol) {
        final ticker = tickers[symbol];
        if (ticker == null) {
          return PriceResult.failure(
              symbol, 'No CryptoCompare mapping for "$symbol"');
        }
        final coinData = data[ticker];
        final price = coinData is Map<String, dynamic>
            ? (coinData[tsym] as num?)?.toDouble()
            : null;
        if (price == null || price <= 0) {
          return PriceResult.failure(symbol, 'Invalid price for $ticker');
        }
        return PriceResult(
          symbol: symbol,
          price: price,
          currency: tsym,
          fetchedAt: DateTime.now(),
          success: true,
        );
      }).toList();
    } catch (e) {
      return symbols.map((s) => PriceResult.failure(s, 'Error: $e')).toList();
    }
  }
}
