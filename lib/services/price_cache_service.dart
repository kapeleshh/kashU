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
/// - Stores the last successfully fetched price for every symbol, in each
///   currency it is held in.
/// - Used as a fallback when an API call fails (rate limit, offline, timeout).
/// - Prevents redundant network calls within the TTL window on app restart.
///
/// Freshness has two tiers: entries younger than [defaultTtl] (30 min) are
/// fresh; older entries are still served as a fallback — flagged stale via
/// [PriceResult.isStale] — up to [maxStaleAge] (7 days), after which they
/// are treated as missing. Unbounded stale prices in a finance app are worse
/// than an honest failure.
///
/// Each entry is stored as a JSON-encoded string under [keyFor] (symbol and
/// currency) so it works cleanly with a plain (untyped) Hive box. Entries
/// from before prices were keyed by currency sit under the bare symbol; they
/// are never read again and go with the next Clear All Data.
class PriceCacheService {
  static const Duration defaultTtl = Duration(minutes: 30);

  /// Hard cap on how old a cached price may be and still be served.
  static const Duration maxStaleAge = Duration(days: 7);

  Box get _box => Hive.box(AppConstants.priceCacheBox);

  /// The key [symbol]'s price in [currency] is cached under, e.g.
  /// `bitcoin:INR` or `GC=F:USD`.
  ///
  /// A cached price is a number in one currency, so the symbol alone is not
  /// a key: the same coin, share or metal held once in INR and once in USD
  /// would overwrite each other, and the offline fallback would then hand
  /// one holding the other's number with no conversion.
  static String keyFor(String symbol, String currency) =>
      '$symbol:${currency.toUpperCase()}';

  /// Store a successful [result] as [PriceResult.symbol]'s price in
  /// [PriceResult.currency]. No-op if the result was a failure, or has no
  /// currency to file it under.
  Future<void> cachePrice(PriceResult result) async {
    if (!result.success || result.currency.isEmpty) return;
    final entry = CachedPriceEntry(
      price: result.price,
      currency: result.currency,
      fetchedAt: result.fetchedAt,
    );
    await _box.put(
        keyFor(result.symbol, result.currency), jsonEncode(entry.toJson()));
  }

  /// The raw [CachedPriceEntry] for [symbol] in [currency], or null if
  /// absent or unreadable.
  CachedPriceEntry? getEntry(String symbol, String currency) {
    final raw = _box.get(keyFor(symbol, currency));
    if (raw is! String) return null;
    try {
      final entry =
          CachedPriceEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      // Belt and braces: never serve a number in some other currency.
      if (entry.currency.toUpperCase() != currency.toUpperCase()) return null;
      return entry;
    } catch (_) {
      return null;
    }
  }

  /// Returns true if a cached entry exists and is younger than [maxAge].
  bool isValid(String symbol, String currency,
      {Duration maxAge = defaultTtl}) {
    final entry = getEntry(symbol, currency);
    if (entry == null) return false;
    return DateTime.now().difference(entry.fetchedAt) < maxAge;
  }

  /// Build a [PriceResult] from the cached price of [symbol] in [currency].
  ///
  /// Returns a failure result if no entry exists or the entry is older than
  /// [maxAge]. Entries older than [defaultTtl] but within [maxAge] are
  /// served with [PriceResult.isStale] set, and keep their original
  /// [PriceResult.fetchedAt] so callers can surface the real price age.
  PriceResult getCachedResult(String symbol, String currency,
      {Duration maxAge = maxStaleAge}) {
    final entry = getEntry(symbol, currency);
    if (entry == null) {
      return PriceResult.failure(
          symbol, 'No cached price for $symbol in $currency');
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

  /// Remove [symbol]'s cached price in [currency].
  Future<void> invalidate(String symbol, String currency) =>
      _box.delete(keyFor(symbol, currency));

  /// Remove all cached prices.
  Future<void> clearAll() => _box.clear();
}
