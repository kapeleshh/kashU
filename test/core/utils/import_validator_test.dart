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
        'createdAt': '2024-01-15T00:00:00.000',
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

  group('ImportValidator.validateAssets', () {
    test('rejects a type index beyond AssetType', () {
      expect(ImportValidator.validateAssets([validAsset()..['type'] = 8]),
          contains('"type" must be an integer 0–7'));
    });

    test('rejects non-finite numbers', () {
      // jsonDecode turns an overflowing literal (1e999) into infinity.
      expect(
          ImportValidator.validateAssets(
              [validAsset()..['currentPrice'] = double.infinity]),
          contains('finite'));
      expect(
          ImportValidator.validateAssets(
              [validAsset()..['quantity'] = double.nan]),
          contains('finite'));
    });

    test('rejects a non-text optional field', () {
      expect(ImportValidator.validateAssets([validAsset()..['symbol'] = 42]),
          contains('"symbol" must be text'));
    });

    test('rejects an unparseable priceUpdatedAt but accepts null', () {
      expect(
          ImportValidator.validateAssets(
              [validAsset()..['priceUpdatedAt'] = 'yesterday']),
          contains('"priceUpdatedAt"'));
      expect(
          ImportValidator.validateAssets(
              [validAsset()..['priceUpdatedAt'] = null]),
          isNull);
    });

    test('rejects a repeated asset id', () {
      expect(ImportValidator.validateAssets([validAsset(), validAsset()]),
          contains('Asset[1]."id" appears more than once'));
    });
  });

  group('ImportValidator.validateTransactions', () {
    String? validate(Map<String, dynamic> t) =>
        ImportValidator.validateTransactions([t]);

    test('accepts every TransactionType and nothing past it', () {
      for (var type = 0; type <= 3; type++) {
        expect(validate(validTransaction()..['type'] = type), isNull,
            reason: 'type $type');
      }
      // The old validator accepted 0–6; TransactionType.values[4] throws.
      for (final type in [4, 6, -1]) {
        expect(validate(validTransaction()..['type'] = type),
            contains('"type" must be an integer 0–3'),
            reason: 'type $type');
      }
    });

    test('rejects a missing or invalid createdAt', () {
      expect(validate(validTransaction()..remove('createdAt')),
          contains('"createdAt"'));
      expect(validate(validTransaction()..['createdAt'] = 'not a date'),
          contains('"createdAt"'));
      expect(validate(validTransaction()..['createdAt'] = '1970-01-01'),
          contains('"createdAt"'));
    });

    test(
        'accepts an assetId that matches no asset — the history of a '
        'holding deleted earlier', () {
      expect(validate(validTransaction()..['assetId'] = 'deleted-long-ago'),
          isNull);
    });

    test('still requires a non-empty assetId', () {
      expect(validate(validTransaction()..['assetId'] = ''),
          contains('"assetId" must be a non-empty string'));
      expect(validate(validTransaction()..remove('assetId')),
          contains('"assetId" must be a non-empty string'));
    });

    test('rejects NaN and infinite amounts', () {
      expect(validate(validTransaction()..['amount'] = double.nan),
          contains('"amount" must be a finite number'));
      expect(validate(validTransaction()..['price'] = double.negativeInfinity),
          contains('"price" must be a finite number'));
    });

    test('rejects a repeated transaction id', () {
      expect(
          ImportValidator.validateTransactions(
              [validTransaction(), validTransaction()]),
          contains('Transaction[1]."id" appears more than once'));
    });
  });
}
