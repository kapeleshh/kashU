import 'package:flutter_test/flutter_test.dart';
import 'package:kashu/core/constants/app_constants.dart';
import 'package:kashu/core/utils/import_validator.dart';

void main() {
  Map<String, dynamic> validAsset() => {
        'id': 'a1',
        'name': 'Reliance',
        'currency': 'INR',
        'quantity': 10,
        'purchasePrice': 2400.0,
        'currentPrice': 2500.0,
        'type': 0,
        'purchaseDate': '2024-01-15T00:00:00.000',
        'createdAt': '2024-01-15T00:00:00.000',
        'updatedAt': '2024-01-15T00:00:00.000',
      };

  Map<String, dynamic> validTransaction() => {
        'id': 't1',
        'assetId': 'a1',
        'currency': 'INR',
        'quantity': 10,
        'price': 2400.0,
        'amount': 24000.0,
        'type': 0,
        'date': '2024-01-15T00:00:00.000',
      };

  group('ImportValidator.validateEnvelope', () {
    test('accepts the current backup format version', () {
      expect(
        ImportValidator.validateEnvelope({
          'schemaVersion': AppConstants.backupFormatVersion,
          'assets': [],
          'transactions': [],
        }),
        isNull,
      );
    });

    test('accepts legacy version string "1.0"', () {
      expect(
        ImportValidator.validateEnvelope({
          'version': '1.0',
          'assets': [],
          'transactions': [],
        }),
        isNull,
      );
    });

    test('rejects a newer (unknown) version', () {
      final error = ImportValidator.validateEnvelope({'schemaVersion': 3});
      expect(error, contains('Unsupported backup version'));
    });

    test('rejects a missing version', () {
      final error = ImportValidator.validateEnvelope({'assets': []});
      expect(error, contains('Unsupported backup version'));
    });

    test('rejects non-list assets/transactions', () {
      expect(
        ImportValidator.validateEnvelope({
          'schemaVersion': 2,
          'assets': 'not a list',
        }),
        contains('"assets" must be a list'),
      );
    });

    test('currentSchemaVersion matches the shared constant', () {
      expect(ImportValidator.currentSchemaVersion,
          AppConstants.backupFormatVersion);
    });
  });

  group('ImportValidator round trip', () {
    test('an export-shaped envelope with valid items passes all validators',
        () {
      final envelope = {
        'schemaVersion': AppConstants.backupFormatVersion,
        'exportedAt': '2026-07-06T00:00:00.000',
        'assets': [validAsset()],
        'transactions': [validTransaction()],
      };

      expect(ImportValidator.validateEnvelope(envelope), isNull);
      expect(
          ImportValidator.validateAssets(envelope['assets'] as List), isNull);
      expect(
          ImportValidator.validateTransactions(
              envelope['transactions'] as List),
          isNull);
    });

    test('invalid asset is reported with its index', () {
      final asset = validAsset()..['quantity'] = -5;
      expect(ImportValidator.validateAssets([asset]),
          contains('Asset[0]."quantity"'));
    });
  });
}
