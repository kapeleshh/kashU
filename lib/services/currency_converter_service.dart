import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// Result of a currency conversion fetch
class ExchangeRateResult {
  final String base;
  final Map<String, double> rates;
  final DateTime fetchedAt;
  final bool success;
  final String? error;

  const ExchangeRateResult({
    required this.base,
    required this.rates,
    required this.fetchedAt,
    required this.success,
    this.error,
  });

  factory ExchangeRateResult.failure(String error) {
    return ExchangeRateResult(
      base: 'USD',
      rates: {},
      fetchedAt: DateTime.now(),
      success: false,
      error: error,
    );
  }

  /// Get conversion rate: 1 [base] → [targetCurrency]
  double getRate(String targetCurrency) {
    if (targetCurrency == base) return 1.0;
    return rates[targetCurrency] ?? 1.0;
  }

  /// Convert [amount] from [base] to [targetCurrency]
  double convert(double amount, String targetCurrency) {
    return amount * getRate(targetCurrency);
  }
}

/// Fetches live exchange rates using the free Open Exchange Rates API.
/// No API key required for the latest USD-based rates endpoint.
///
/// API: https://open.er-api.com/v6/latest/USD
/// On web, requests are routed through a local proxy to bypass CORS.
class CurrencyConverterService {
  static const String _baseUrl = 'https://open.er-api.com/v6/latest';

  /// Local proxy base URL (used on web to bypass CORS)
  static const String _proxyBase = 'http://localhost:8080/proxy?url=';

  /// Grams per troy ounce — used to convert gold price
  static const double gramsPerTroyOz = 31.1035;

  final http.Client _client;

  /// In-memory cache of the last fetched rates (avoids redundant calls)
  ExchangeRateResult? _cachedRates;
  DateTime? _cacheTime;

  /// Cache duration: 30 minutes
  static const _cacheDuration = Duration(minutes: 30);

  CurrencyConverterService({http.Client? client})
      : _client = client ?? http.Client();

  /// Build the request URL — uses proxy on web, direct on mobile/desktop
  Uri _buildUrl(String directUrl) {
    if (kIsWeb) {
      return Uri.parse('$_proxyBase${Uri.encodeComponent(directUrl)}');
    }
    return Uri.parse(directUrl);
  }

  /// Fetch latest exchange rates with base = USD.
  /// Returns cached result if fetched within the last 30 minutes.
  Future<ExchangeRateResult> fetchRates({bool forceRefresh = false}) async {
    // Return cached rates if still fresh
    if (!forceRefresh &&
        _cachedRates != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheDuration) {
      return _cachedRates!;
    }

    final url = _buildUrl('$_baseUrl/USD');

    try {
      final response = await _client.get(
        url,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return ExchangeRateResult.failure(
          'HTTP ${response.statusCode}: Could not fetch exchange rates',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (data['result'] != 'success') {
        return ExchangeRateResult.failure(
          'Exchange rate API returned: ${data['result']}',
        );
      }

      final ratesRaw = data['rates'] as Map<String, dynamic>;
      final rates = ratesRaw.map(
        (key, value) => MapEntry(key, (value as num).toDouble()),
      );

      final result = ExchangeRateResult(
        base: 'USD',
        rates: rates,
        fetchedAt: DateTime.now(),
        success: true,
      );

      // Cache the result
      _cachedRates = result;
      _cacheTime = DateTime.now();

      return result;
    } on http.ClientException catch (e) {
      return ExchangeRateResult.failure('Network error: ${e.message}');
    } catch (e) {
      return ExchangeRateResult.failure('Unexpected error: $e');
    }
  }

  /// Convert a USD amount to the target currency using live rates.
  /// Falls back to hardcoded approximate rates if network is unavailable.
  Future<double> convertFromUSD(double usdAmount, String targetCurrency) async {
    if (targetCurrency == 'USD') return usdAmount;

    final rates = await fetchRates();
    if (rates.success) {
      return rates.convert(usdAmount, targetCurrency);
    }

    // Fallback to hardcoded approximate rates (used when offline)
    return usdAmount * fallbackRate(targetCurrency);
  }

  /// Convert gold price from USD per troy oz → target currency per gram
  ///
  /// Yahoo Finance `GC=F` returns price in USD per troy oz.
  /// Gold in India (and most apps) is tracked per gram.
  Future<double> goldUSDPerOzToTargetPerGram(
    double usdPerTroyOz,
    String targetCurrency,
  ) async {
    // Step 1: USD/troy oz → USD/gram
    final usdPerGram = usdPerTroyOz / gramsPerTroyOz;

    // Step 2: USD/gram → targetCurrency/gram
    return convertFromUSD(usdPerGram, targetCurrency);
  }

  /// Hardcoded approximate fallback rates (USD → target) for offline mode.
  /// Public so other services (e.g. GoldPriceService) can use them.
  static double fallbackRate(String currency) {
    const fallbacks = {
      'INR': 83.5,
      'EUR': 0.92,
      'GBP': 0.79,
      'JPY': 149.5,
      'AED': 3.67,
      'SGD': 1.34,
      'AUD': 1.53,
      'CAD': 1.36,
      'CHF': 0.88,
    };
    return fallbacks[currency] ?? 1.0;
  }
}
