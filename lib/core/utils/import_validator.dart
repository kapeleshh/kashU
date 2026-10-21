import '../../data/models/asset_type.dart';
import '../../data/models/transaction_type.dart';
import '../constants/app_constants.dart';

/// Validates KashU backup JSON before it is written to the database.
///
/// Returns null on success, or a human-readable error message on failure.
/// Every check that [Asset.fromJson] / [Transaction.fromJson] relies on lives
/// here, so a backup that passes can be decoded into model objects without
/// throwing — which is what lets an import parse the whole file before it
/// writes anything (see BackupService.parse).
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
    final ids = <String>{};
    for (int i = 0; i < rawList.length; i++) {
      final item = rawList[i];
      if (item is! Map<String, dynamic>) {
        return 'Asset[$i] is not an object.';
      }
      final err = _validateAsset(item, i);
      if (err != null) return err;
      // A repeated id would silently overwrite its twin and make the
      // import's "N assets" preview a lie.
      if (!ids.add(item['id'] as String)) {
        return 'Asset[$i]."id" appears more than once in this backup.';
      }
    }
    return null;
  }

  /// Validate a list of raw transaction maps.
  ///
  /// [knownAssetIds] are the assets a transaction may belong to: the ones in
  /// the same backup plus the ones already on this device. A transaction
  /// pointing anywhere else is rejected — it could only come from a damaged
  /// or hand-edited file, and would surface as unattributed history in the
  /// Activity screen and the tax export.
  static String? validateTransactions(
    List<dynamic> rawList, {
    required Set<String> knownAssetIds,
  }) {
    final ids = <String>{};
    for (int i = 0; i < rawList.length; i++) {
      final item = rawList[i];
      if (item is! Map<String, dynamic>) {
        return 'Transaction[$i] is not an object.';
      }
      final err = _validateTransaction(item, i, knownAssetIds);
      if (err != null) return err;
      if (!ids.add(item['id'] as String)) {
        return 'Transaction[$i]."id" appears more than once in this backup.';
      }
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
    // Optional string fields
    for (final key in ['symbol', 'platform', 'notes']) {
      if (a[key] != null && a[key] is! String) {
        return 'Asset[$idx]."$key" must be text.';
      }
    }
    // Required numeric fields
    for (final key in ['quantity', 'purchasePrice', 'currentPrice']) {
      final err = _checkNumber(a[key], 'Asset[$idx]."$key"');
      if (err != null) return err;
      if ((a[key] as num) < 0) {
        return 'Asset[$idx]."$key" must not be negative.';
      }
    }
    // type index
    final typeIdx = a['type'];
    final maxType = AssetType.values.length - 1;
    if (typeIdx is! int || typeIdx < 0 || typeIdx > maxType) {
      return 'Asset[$idx]."type" must be an integer 0–$maxType.';
    }
    // date fields
    for (final key in ['purchaseDate', 'createdAt', 'updatedAt']) {
      if (!_isValidDate(a[key])) {
        return 'Asset[$idx]."$key" must be a valid ISO-8601 date string.';
      }
    }
    if (a['priceUpdatedAt'] != null && !_isValidDate(a['priceUpdatedAt'])) {
      return 'Asset[$idx]."priceUpdatedAt" must be a valid ISO-8601 date '
          'string.';
    }
    // purchaseDate must not be in the future
    final purchaseDate = DateTime.tryParse(a['purchaseDate'] as String? ?? '');
    if (purchaseDate != null && purchaseDate.isAfter(DateTime.now())) {
      return 'Asset[$idx]."purchaseDate" must not be in the future.';
    }
    return null;
  }

  static String? _validateTransaction(
      Map<String, dynamic> t, int idx, Set<String> knownAssetIds) {
    for (final key in ['id', 'assetId', 'currency']) {
      if (t[key] is! String || (t[key] as String).isEmpty) {
        return 'Transaction[$idx]."$key" must be a non-empty string.';
      }
    }
    if (!knownAssetIds.contains(t['assetId'])) {
      return 'Transaction[$idx] belongs to an asset that is neither in this '
          'backup nor in KashU.';
    }
    if (t['notes'] != null && t['notes'] is! String) {
      return 'Transaction[$idx]."notes" must be text.';
    }
    for (final key in ['quantity', 'price', 'amount']) {
      final err = _checkNumber(t[key], 'Transaction[$idx]."$key"');
      if (err != null) return err;
    }
    final typeIdx = t['type'];
    final maxType = TransactionType.values.length - 1;
    if (typeIdx is! int || typeIdx < 0 || typeIdx > maxType) {
      return 'Transaction[$idx]."type" must be an integer 0–$maxType.';
    }
    for (final key in ['date', 'createdAt']) {
      if (!_isValidDate(t[key])) {
        return 'Transaction[$idx]."$key" must be a valid ISO-8601 date '
            'string.';
      }
    }
    return null;
  }

  /// Null if [value] is a finite number. `jsonDecode` turns an overflowing
  /// literal such as 1e999 into infinity, so "is a num" alone is not enough.
  static String? _checkNumber(dynamic value, String label) {
    if (value is! num) {
      return '$label must be a number, got ${value.runtimeType}.';
    }
    if (!value.isFinite) return '$label must be a finite number.';
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
