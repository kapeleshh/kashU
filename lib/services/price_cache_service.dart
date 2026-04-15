import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/constants/app_constants.dart';
import 'price_service.dart';

/// A single cached price entry stored in Hive.
class CachedPriceEntry {
  final double price;
  final String currency;
  final DateTime fetchedAt;

  const CachedPriceEntry({
    required this.price,
    required this.currency,
    required this.fetchedAt,
  });

  factory CachedPriceEntry.fromJson(Map<String, dynamic> json) {
    return CachedPriceEntry(
      price: (json['price'] as num).toDouble(),
      currency: json['currency'] as String,
      fetchedAt: DateTime.parse(json['fetchedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'price': price,
        'currency': currency,
        'fetchedAt': fetchedAt.toIso8601String(),
      };
}

/// Hive-backed persistent price cache with a 30-minute TTL.
///
/// Purpose:
/// - Stores the last successfully fetched price for every symbol.
/// - Used as a fallback when an API call fails (rate limit, offline, timeout).
/// - Prevents redundant network calls within the TTL window on app restart.
///
/// Each entry is stored as a JSON-encoded string keyed by symbol so it
/// works cleanly with a plain (untyped) Hive box.
class PriceCacheService {
  static const Duration defaultTtl = Duration(minutes: 30);

  Box get _box => Hive.box(AppConstants.priceCacheBox);

  /// Store a successful [PriceResult] in the cache.
  /// No-op if the result was a failure.
  Future<void> cachePrice(PriceResult result) async {
    if (!result.success) return;
    final entry = CachedPriceEntry(
      price: result.price,
      currency: result.currency,
      fetchedAt: result.fetchedAt,
    );
    await _box.put(result.symbol, jsonEncode(entry.toJson()));
  }

  /// Retrieve the raw [CachedPriceEntry] for [symbol], or null if absent.
  CachedPriceEntry? getEntry(String symbol) {
    final raw = _box.get(symbol) as String?;
    if (raw == null) return null;
    try {
      return CachedPriceEntry.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Returns true if a cached entry exists and is younger than [maxAge].
  bool isValid(String symbol, {Duration maxAge = defaultTtl}) {
    final entry = getEntry(symbol);
    if (entry == null) return false;
    return DateTime.now().difference(entry.fetchedAt) < maxAge;
  }

  /// Build a [PriceResult] from the cached entry for [symbol].
  /// Returns a failure result if no entry exists.
  PriceResult getCachedResult(String symbol) {
    final entry = getEntry(symbol);
    if (entry == null) {
      return PriceResult.failure(symbol, 'No cached price for $symbol');
    }
    return PriceResult(
      symbol: symbol,
      price: entry.price,
      currency: entry.currency,
      fetchedAt: entry.fetchedAt,
      success: true,
    );
  }

  /// Remove a single symbol from the cache.
  Future<void> invalidate(String symbol) => _box.delete(symbol);

  /// Remove all cached prices.
  Future<void> clearAll() => _box.clear();
}
