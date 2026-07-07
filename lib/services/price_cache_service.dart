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

/// Hive-backed persistent price cache.
///
/// Purpose:
/// - Stores the last successfully fetched price for every symbol.
/// - Used as a fallback when an API call fails (rate limit, offline, timeout).
/// - Prevents redundant network calls within the TTL window on app restart.
///
/// Freshness has two tiers: entries younger than [defaultTtl] (30 min) are
/// fresh; older entries are still served as a fallback — flagged stale via
/// [PriceResult.isStale] — up to [maxStaleAge] (7 days), after which they
/// are treated as missing. Unbounded stale prices in a finance app are worse
/// than an honest failure.
///
/// Each entry is stored as a JSON-encoded string keyed by symbol so it
/// works cleanly with a plain (untyped) Hive box.
class PriceCacheService {
  static const Duration defaultTtl = Duration(minutes: 30);

  /// Hard cap on how old a cached price may be and still be served.
  static const Duration maxStaleAge = Duration(days: 7);

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
  ///
  /// Returns a failure result if no entry exists or the entry is older than
  /// [maxAge]. Entries older than [defaultTtl] but within [maxAge] are
  /// served with [PriceResult.isStale] set, and keep their original
  /// [PriceResult.fetchedAt] so callers can surface the real price age.
  PriceResult getCachedResult(String symbol, {Duration maxAge = maxStaleAge}) {
    final entry = getEntry(symbol);
    if (entry == null) {
      return PriceResult.failure(symbol, 'No cached price for $symbol');
    }
    final age = DateTime.now().difference(entry.fetchedAt);
    if (age > maxAge) {
      return PriceResult.failure(
        symbol,
        'Cached price for $symbol is older than ${maxAge.inDays} day(s)',
      );
    }
    return PriceResult(
      symbol: symbol,
      price: entry.price,
      currency: entry.currency,
      fetchedAt: entry.fetchedAt,
      success: true,
      isStale: age > defaultTtl,
    );
  }

  /// Remove a single symbol from the cache.
  Future<void> invalidate(String symbol) => _box.delete(symbol);

  /// Remove all cached prices.
  Future<void> clearAll() => _box.clear();
}
