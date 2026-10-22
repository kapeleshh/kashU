import '../constants/app_strings.dart';

/// What is wrong with a number, as judged by [AmountValidator.problemOf].
enum AmountProblem {
  /// Not a number at all: blank, text, or the wrong JSON type.
  notANumber,

  /// NaN or ±infinity. `double.tryParse` accepts "NaN" and "Infinity", and
  /// `jsonDecode` turns an overflowing literal such as 1e999 into infinity,
  /// so "it parsed" is not enough.
  notFinite,

  /// Below zero.
  negative,

  /// Exactly zero where zero means nothing (a purchase price, a new
  /// holding's quantity, a deposit's rate).
  zero,
}

/// The one set of rules for every amount KashU stores — a quantity, a price,
/// a rate. The Add/Edit Asset form, the manual price update, the deposit
/// calculator, the sell flow (through TransactionValidator) and backup
/// imports (through ImportValidator) all judge numbers here, so a figure one
/// path accepts is never refused, or quietly stored, by another.
///
/// Each caller decides only whether zero is meaningful for its field.
abstract final class AmountValidator {
  static const String invalidNumber = 'Enter a valid number';
  static const String mustBePositive = 'Must be more than 0';
  static const String cannotBeNegative = "Can't be negative";

  /// [text] as a finite number, or null when it is blank, not a number, NaN
  /// or infinite. Range rules are [check]'s job.
  static double? parse(String? text) {
    final value = double.tryParse(text?.trim() ?? '');
    return value != null && value.isFinite ? value : null;
  }

  /// What is wrong with [value] (any JSON or Dart value), or null when it is
  /// a finite number that is not negative and — unless [allowZero] — not 0.
  static AmountProblem? problemOf(Object? value, {bool allowZero = false}) {
    if (value is! num) return AmountProblem.notANumber;
    if (!value.isFinite) return AmountProblem.notFinite;
    if (value < 0) return AmountProblem.negative;
    if (value == 0 && !allowZero) return AmountProblem.zero;
    return null;
  }

  /// The inline message for [problem]. Where zero is not allowed, a negative
  /// figure gets the same "more than 0" message as zero itself.
  static String message(AmountProblem problem, {bool allowZero = false}) {
    switch (problem) {
      case AmountProblem.notANumber:
      case AmountProblem.notFinite:
        return invalidNumber;
      case AmountProblem.negative:
        return allowZero ? cannotBeNegative : mustBePositive;
      case AmountProblem.zero:
        return mustBePositive;
    }
  }

  /// The message for an already-parsed [value], or null when it is valid.
  static String? check(double? value, {bool allowZero = false}) {
    final problem = problemOf(value, allowZero: allowZero);
    return problem == null ? null : message(problem, allowZero: allowZero);
  }

  /// A form-field validator for typed [text]. Blank is "required" unless
  /// [required] is false, in which case it is simply not an error yet.
  static String? validate(
    String? text, {
    bool allowZero = false,
    bool required = true,
  }) {
    if (text == null || text.trim().isEmpty) {
      return required ? AppStrings.errorRequired : null;
    }
    return check(double.tryParse(text.trim()), allowZero: allowZero);
  }
}
