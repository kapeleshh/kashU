import 'dart:convert';

import 'package:hive/hive.dart';

import '../core/constants/app_constants.dart';

/// A single day's portfolio snapshot.
///
/// [total] is the portfolio value in the base currency at capture time.
/// [assetValues] maps asset id → that asset's value in its OWN currency
/// (used for per-asset sparklines, where the trend shape — not the absolute
/// currency — is what matters).
class DailySnapshot {
  final DateTime date; // normalised to the day (local)
  final double total;
  final Map<String, double> assetValues;

  const DailySnapshot({
    required this.date,
    required this.total,
    required this.assetValues,
  });

  /// Day key `yyyy-MM-dd`, also the Hive box key.
  static String keyFor(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String get key => keyFor(date);

  Map<String, dynamic> toJson() => {
        'date': key,
        'total': total,
        'assets': assetValues,
      };

  static DailySnapshot? fromJson(Map<String, dynamic> json) {
    final dateStr = json['date'] as String?;
    if (dateStr == null) return null;
    final parts = dateStr.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    final raw = json['assets'];
    final assets = <String, double>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        if (k is String && v is num) assets[k] = v.toDouble();
      });
    }
    return DailySnapshot(
      date: DateTime(y, m, d),
      total: (json['total'] as num?)?.toDouble() ?? 0,
      assetValues: assets,
    );
  }
}

/// Persists one portfolio price snapshot per day (in [AppConstants.priceHistoryBox],
/// a plain JSON-backed box — no Hive adapter/schema migration needed) so the app
/// can show an honest day-over-day change and a real per-asset sparkline.
///
/// Design (agreed): one snapshot per calendar day, retained [retention].
/// "Today's change" compares the current total against the most recent
/// snapshot from a PRIOR day.
class PriceHistoryService {
  static const Duration retention = Duration(days: 90);

  final Box? _boxOverride;
  PriceHistoryService({Box? box}) : _boxOverride = box;

  Box get _box => _boxOverride ?? Hive.box(AppConstants.priceHistoryBox);

  /// Whether the backing box is available. Guards reads so a screen or test
  /// that renders without the box open degrades to "no history" instead of
  /// throwing.
  bool get _isOpen =>
      _boxOverride != null || Hive.isBoxOpen(AppConstants.priceHistoryBox);

  /// Record (or overwrite) today's snapshot, then prune old entries.
  ///
  /// [total] is in the base currency; [assetValues] are per-asset native
  /// values. Passing [now] is for tests.
  Future<void> recordDailySnapshot({
    required double total,
    required Map<String, double> assetValues,
    DateTime? now,
  }) async {
    if (!_isOpen) return;
    final today = now ?? DateTime.now();
    final snap = DailySnapshot(
      date: DateTime(today.year, today.month, today.day),
      total: total,
      assetValues: assetValues,
    );
    await _box.put(snap.key, jsonEncode(snap.toJson()));
    await _prune(today);
  }

  /// All snapshots, oldest → newest.
  List<DailySnapshot> _all() {
    if (!_isOpen) return const [];
    final out = <DailySnapshot>[];
    for (final v in _box.values) {
      if (v is! String) continue;
      try {
        final snap = DailySnapshot.fromJson(
            jsonDecode(v) as Map<String, dynamic>);
        if (snap != null) out.add(snap);
      } catch (_) {
        // Skip corrupt entries.
      }
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  /// The most recent snapshot dated BEFORE today, or null if none.
  /// This is the baseline for "today's change".
  DailySnapshot? previousDaySnapshot({DateTime? now}) {
    final today = now ?? DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    DailySnapshot? latestPrior;
    for (final s in _all()) {
      if (s.date.isBefore(startOfToday)) {
        latestPrior = s; // _all() is sorted ascending, so last wins
      }
    }
    return latestPrior;
  }

  /// Total from [previousDaySnapshot], or null. (Kept for callers/tests that
  /// only need the portfolio total; today's-change now uses the per-asset
  /// values on the snapshot to isolate price movement from holdings changes.)
  double? previousDayTotal({DateTime? now}) =>
      previousDaySnapshot(now: now)?.total;

  /// Ordered value series for [assetId] across retained snapshots (oldest →
  /// newest). Days where the asset had no recorded value are skipped.
  List<double> assetSeries(String assetId) {
    final out = <double>[];
    for (final s in _all()) {
      final v = s.assetValues[assetId];
      if (v != null) out.add(v);
    }
    return out;
  }

  /// Number of stored snapshots (for tests / diagnostics).
  int get snapshotCount => _isOpen ? _box.length : 0;

  Future<void> _prune(DateTime now) async {
    final cutoff = now.subtract(retention);
    final staleKeys = <dynamic>[];
    for (final key in _box.keys) {
      final v = _box.get(key);
      if (v is! String) {
        staleKeys.add(key);
        continue;
      }
      try {
        final snap =
            DailySnapshot.fromJson(jsonDecode(v) as Map<String, dynamic>);
        if (snap == null || snap.date.isBefore(cutoff)) staleKeys.add(key);
      } catch (_) {
        staleKeys.add(key);
      }
    }
    if (staleKeys.isNotEmpty) await _box.deleteAll(staleKeys);
  }
}
