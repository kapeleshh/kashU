import '../constants/app_constants.dart';

/// Validates KashU backup JSON before it is written to the database.
///
/// Returns null on success, or a human-readable error message on failure.
/// Call this before passing data to [AssetRepository.importFromJson] or
/// [TransactionRepository.importFromJson].
///
/// The version checked here is the backup *file format* version
/// ([AppConstants.backupFormatVersion]) — not the Hive on-disk schema
/// version managed by HiveMigrationService. The two evolve independently.
class ImportValidator {
  static const int _currentSchemaVersion = AppConstants.backupFormatVersion;
  static const List<int> _supportedVersions = [1, 2];

  /// Validate the top-level backup envelope.
  ///
  /// Returns null if valid, or an error string describing what is wrong.
  static String? validateEnvelope(Map<String, dynamic> data) {
    // Accept both legacy 'version' string ("1.0") and numeric 'schemaVersion'
    final schemaVersion = _parseSchemaVersion(data);
    if (!_supportedVersions.contains(schemaVersion)) {
      return 'Unsupported backup version "$schemaVersion". '
          'This backup may be from a newer version of KashU.';
    }

    if (data.containsKey('assets') && data['assets'] is! List) {
      return '"assets" must be a list, got ${data['assets'].runtimeType}.';
    }
    if (data.containsKey('transactions') && data['transactions'] is! List) {
      return '"transactions" must be a list, '
          'got ${data['transactions'].runtimeType}.';
    }
    return null;
  }

  /// Validate a list of raw asset maps.
  ///
  /// Returns null if all items are valid, or an error describing the first
  /// invalid item (with its index).
  static String? validateAssets(List<dynamic> rawList) {
    for (int i = 0; i < rawList.length; i++) {
      final item = rawList[i];
      if (item is! Map<String, dynamic>) {
        return 'Asset[$i] is not an object.';
      }
      final err = _validateAsset(item, i);
      if (err != null) return err;
    }
    return null;
  }

  /// Validate a list of raw transaction maps.
  static String? validateTransactions(List<dynamic> rawList) {
    for (int i = 0; i < rawList.length; i++) {
      final item = rawList[i];
      if (item is! Map<String, dynamic>) {
        return 'Transaction[$i] is not an object.';
      }
      final err = _validateTransaction(item, i);
      if (err != null) return err;
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  static int _parseSchemaVersion(Map<String, dynamic> data) {
    // New format: schemaVersion: 2
    if (data['schemaVersion'] is int) return data['schemaVersion'] as int;
    // Legacy format: version: "1.0"
    final v = data['version'];
    if (v is String) {
      final parts = v.split('.');
      return int.tryParse(parts.first) ?? 0;
    }
    return 0;
  }

  static String? _validateAsset(Map<String, dynamic> a, int idx) {
    // Required string fields
    for (final key in ['id', 'name', 'currency']) {
      if (a[key] is! String || (a[key] as String).isEmpty) {
        return 'Asset[$idx]."$key" must be a non-empty string.';
      }
    }
    // Required numeric fields
    for (final key in ['quantity', 'purchasePrice', 'currentPrice']) {
      if (a[key] is! num) {
        return 'Asset[$idx]."$key" must be a number, got ${a[key].runtimeType}.';
      }
      final v = (a[key] as num).toDouble();
      if (v < 0) {
        return 'Asset[$idx]."$key" must not be negative.';
      }
    }
    // type index
    final typeIdx = a['type'];
    if (typeIdx is! int || typeIdx < 0 || typeIdx > 7) {
      return 'Asset[$idx]."type" must be an integer 0–7.';
    }
    // date fields
    for (final key in ['purchaseDate', 'createdAt', 'updatedAt']) {
      if (!_isValidDate(a[key])) {
        return 'Asset[$idx]."$key" must be a valid ISO-8601 date string.';
      }
    }
    // purchaseDate must not be in the future
    final purchaseDate = DateTime.tryParse(a['purchaseDate'] as String? ?? '');
    if (purchaseDate != null && purchaseDate.isAfter(DateTime.now())) {
      return 'Asset[$idx]."purchaseDate" must not be in the future.';
    }
    return null;
  }

  static String? _validateTransaction(Map<String, dynamic> t, int idx) {
    for (final key in ['id', 'assetId', 'currency']) {
      if (t[key] is! String || (t[key] as String).isEmpty) {
        return 'Transaction[$idx]."$key" must be a non-empty string.';
      }
    }
    for (final key in ['quantity', 'price', 'amount']) {
      if (t[key] is! num) {
        return 'Transaction[$idx]."$key" must be a number.';
      }
    }
    final typeIdx = t['type'];
    if (typeIdx is! int || typeIdx < 0 || typeIdx > 6) {
      return 'Transaction[$idx]."type" must be an integer 0–6.';
    }
    if (!_isValidDate(t['date'])) {
      return 'Transaction[$idx]."date" must be a valid ISO-8601 date string.';
    }
    return null;
  }

  static bool _isValidDate(dynamic value) {
    if (value is! String) return false;
    final dt = DateTime.tryParse(value);
    if (dt == null) return false;
    // Sanity-check: must be between 1990 and 10 years from now
    final now = DateTime.now();
    return dt.isAfter(DateTime(1990)) &&
        dt.isBefore(now.add(const Duration(days: 3650)));
  }

  /// The schema version written into every new export.
  static int get currentSchemaVersion => _currentSchemaVersion;
}
