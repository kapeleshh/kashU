import 'package:flutter_test/flutter_test.dart';
import 'package:kashu/core/constants/app_strings.dart';
import 'package:kashu/core/utils/amount_validator.dart';
import 'package:kashu/core/utils/import_validator.dart';
import 'package:kashu/core/utils/transaction_validator.dart';

void main() {
  group('AmountValidator.parse', () {
    test('reads plain and padded decimals', () {
      expect(AmountValidator.parse('12.5'), 12.5);
      expect(AmountValidator.parse('  7 '), 7);
      expect(AmountValidator.parse('1e3'), 1000);
      expect(AmountValidator.parse('-3'), -3); // range is check's job
    });

    test('returns null for blank, text and non-finite input', () {
      for (final text in [null, '', '  ', 'abc', 'NaN', 'Infinity',
          '-Infinity', '1e999']) {
        expect(AmountValidator.parse(text), isNull, reason: '"$text"');
      }
    });
  });

  group('AmountValidator.problemOf', () {
    test('classifies every kind of bad value', () {
      expect(AmountValidator.problemOf(null), AmountProblem.notANumber);
      expect(AmountValidator.problemOf('5'), AmountProblem.notANumber);
      expect(AmountValidator.problemOf(double.nan), AmountProblem.notFinite);
      expect(AmountValidator.problemOf(double.infinity),
          AmountProblem.notFinite);
      expect(AmountValidator.problemOf(-0.01), AmountProblem.negative);
      expect(AmountValidator.problemOf(0), AmountProblem.zero);
      expect(AmountValidator.problemOf(0.01), isNull);
    });

    test('zero is fine only where the caller allows it', () {
      expect(AmountValidator.problemOf(0, allowZero: true), isNull);
      expect(AmountValidator.problemOf(-1, allowZero: true),
          AmountProblem.negative);
    });
  });

  group('AmountValidator.validate (form fields)', () {
    test('requires a value unless told otherwise', () {
      expect(AmountValidator.validate(''), AppStrings.errorRequired);
      expect(AmountValidator.validate(' ', required: false), isNull);
    });

    test('rejects NaN and Infinity, which double.tryParse accepts', () {
      expect(double.tryParse('NaN'), isNotNull);
      expect(AmountValidator.validate('NaN'), AmountValidator.invalidNumber);
      expect(AmountValidator.validate('Infinity'),
          AmountValidator.invalidNumber);
      expect(AmountValidator.validate('-Infinity', allowZero: true),
          AmountValidator.invalidNumber);
    });

    test('negative and zero messages depend on whether zero is allowed', () {
      expect(AmountValidator.validate('-5'), AmountValidator.mustBePositive);
      expect(AmountValidator.validate('0'), AmountValidator.mustBePositive);
      expect(AmountValidator.validate('-5', allowZero: true),
          AmountValidator.cannotBeNegative);
      expect(AmountValidator.validate('0', allowZero: true), isNull);
      expect(AmountValidator.validate('42.5'), isNull);
    });
  });

  group('the other validators agree with it', () {
    test('TransactionValidator.positive is the same rule', () {
      for (final v in [null, double.nan, double.infinity, -1.0, 0.0, 2.0]) {
        expect(TransactionValidator.positive(v), AmountValidator.check(v),
            reason: '$v');
      }
    });

    test('ImportValidator refuses what the forms refuse', () {
      Map<String, dynamic> asset(Object? price) => {
            'id': 'a1',
            'name': 'Reliance',
            'currency': 'INR',
            'quantity': 1,
            'purchasePrice': 10.0,
            'currentPrice': price,
            'type': 0,
            'purchaseDate': '2024-01-15T00:00:00.000',
            'createdAt': '2024-01-15T00:00:00.000',
            'updatedAt': '2024-01-15T00:00:00.000',
          };
      expect(ImportValidator.validateAssets([asset(double.infinity)]),
          contains('finite'));
      expect(ImportValidator.validateAssets([asset(-1.0)]),
          contains('must not be negative'));
      // A 0 price is valid in the form's current-price field and here.
      expect(ImportValidator.validateAssets([asset(0.0)]), isNull);
    });
  });
}
