import 'dart:convert';

import '../core/utils/import_validator.dart';
import '../data/models/asset.dart';
import '../data/models/transaction.dart';

/// A backup file decoded into model objects — validated in full, not yet
/// written anywhere.
class ParsedBackup {
  final List<Asset> assets;
  final List<Transaction> transactions;

  /// When the backup was exported, if the file says.
  final DateTime? exportedAt;

  const ParsedBackup({
    required this.assets,
    required this.transactions,
    this.exportedAt,
  });
}

/// Builds and reads KashU backup files — the JSON written by Settings ›
/// Export Data and read back by Import Data.
///
/// Static-only, like ExportService: encoding and parsing are pure, so the
/// export → import round trip is unit-testable without a file picker.
class BackupService {
  BackupService._();

  /// Anything larger is not a KashU backup (a big portfolio is a few
  /// hundred KB) and is refused before it is decoded.
  static const int maxBackupBytes = 20 * 1024 * 1024;

  /// The export envelope, in the current backup format version.
  static Map<String, dynamic> buildEnvelope({
    required List<Map<String, dynamic>> assets,
    required List<Map<String, dynamic>> transactions,
    DateTime? exportedAt,
  }) {
    return {
      'schemaVersion': ImportValidator.currentSchemaVersion,
      'exportedAt': (exportedAt ?? DateTime.now()).toIso8601String(),
      'assets': assets,
      'transactions': transactions,
    };
  }

  static String encode(Map<String, dynamic> envelope) =>
      const JsonEncoder.withIndent('  ').convert(envelope);

  /// Decode raw file bytes (what the file picker hands over on every
  /// platform, web included) and [parse] them.
  static ParsedBackup parseBytes(
    List<int> bytes, {
    required Set<String> existingAssetIds,
  }) {
    if (bytes.length > maxBackupBytes) {
      throw const FormatException(
          'This file is too large to be a KashU backup.');
    }
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw const FormatException(
          'This file is not a KashU backup (it is not a text file).');
    }
    return parse(text, existingAssetIds: existingAssetIds);
  }

  /// Validate a whole backup and decode it into model objects.
  ///
  /// Nothing is written: a file that fails any check throws a
  /// [FormatException] whose message is safe to show the user, so an
  /// import either has every record in hand or touches nothing.
  /// [existingAssetIds] are the assets already on this device, which a
  /// backup's transactions may also belong to.
  static ParsedBackup parse(
    String text, {
    required Set<String> existingAssetIds,
  }) {
    // A byte-order mark (some editors add one) is not valid JSON.
    final trimmed = text.replaceFirst('﻿', '').trim();
    final dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException {
      // The decoder's own message quotes the file's contents — keep it out
      // of the UI.
      throw const FormatException(
          'This file is not a KashU backup (it is not valid JSON).');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('This file is not a KashU backup.');
    }

    final envelopeErr = ImportValidator.validateEnvelope(decoded);
    if (envelopeErr != null) throw FormatException(envelopeErr);

    final rawAssets = (decoded['assets'] as List?) ?? const [];
    final rawTransactions = (decoded['transactions'] as List?) ?? const [];

    final assetErr = ImportValidator.validateAssets(rawAssets);
    if (assetErr != null) throw FormatException(assetErr);

    final txErr = ImportValidator.validateTransactions(
      rawTransactions,
      knownAssetIds: {
        ...existingAssetIds,
        for (final a in rawAssets) (a as Map<String, dynamic>)['id'] as String,
      },
    );
    if (txErr != null) throw FormatException(txErr);

    if (rawAssets.isEmpty && rawTransactions.isEmpty) {
      throw const FormatException(
          'This backup contains no assets or transactions.');
    }

    // The validators cover every cast fromJson makes; a throw here means a
    // gap between the two, and must still not reach the database.
    try {
      return ParsedBackup(
        assets: [
          for (final a in rawAssets) Asset.fromJson(a as Map<String, dynamic>),
        ],
        transactions: [
          for (final t in rawTransactions)
            Transaction.fromJson(t as Map<String, dynamic>),
        ],
        exportedAt: decoded['exportedAt'] is String
            ? DateTime.tryParse(decoded['exportedAt'] as String)
            : null,
      );
    } catch (_) {
      throw const FormatException(
          'This backup contains a record KashU cannot read.');
    }
  }
}
