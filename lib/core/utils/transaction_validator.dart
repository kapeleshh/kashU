import 'currency_formatter.dart';

/// Rules for recording a sell, dividend or interest payment.
///
/// Shared by the Record-transaction form, which shows the messages inline,
/// and PortfolioWriteService, which refuses anything the form would reject —
/// so a caller that skips the form cannot write a nonsensical transaction.
/// Each check returns an error message, or null when the input is valid.
abstract final class TransactionValidator {
  /// Relative slack when comparing a sale with the holding, so selling
  /// "everything" — a figure typed back from a rounded display — is neither
  /// refused nor left as a dust remainder.
  static const double quantityTolerance = 1e-9;

  /// A finite, positive number: a quantity, a price or an amount.
  static String? positive(double? value) {
    if (value == null || !value.isFinite) return 'Enter a valid number';
    if (value <= 0) return 'Must be more than 0';
    return null;
  }

  /// The quantity of a sale out of a holding of [holding] units.
  static String? sellQuantity(double? quantity, double holding) {
    final basic = positive(quantity);
    if (basic != null) return basic;
    if (holding <= 0) return 'Nothing left to sell';
    if (exceedsHolding(quantity!, holding)) {
      return 'You hold ${CurrencyFormatter.formatQuantity(holding)}';
    }
    return null;
  }

  /// True when [quantity] is more than [holding], beyond rounding slack.
  static bool exceedsHolding(double quantity, double holding) =>
      quantity - holding > quantityTolerance * _scale(holding);

  /// What is left of [holding] after selling [quantity]. A remainder within
  /// rounding slack is exactly 0, so selling everything closes the holding.
  static double remainingAfterSell(double holding, double quantity) {
    final remaining = holding - quantity;
    return remaining <= quantityTolerance * _scale(holding) ? 0 : remaining;
  }

  /// The trade or payment date: not in the future, and not before the
  /// holding was bought. Compared by calendar day.
  static String? date(
    DateTime date, {
    required DateTime purchaseDate,
    DateTime? now,
  }) {
    final day = _day(date);
    if (day.isAfter(_day(now ?? DateTime.now()))) {
      return "Date can't be in the future";
    }
    if (day.isBefore(_day(purchaseDate))) {
      return "Date can't be before the purchase date "
          '(${formatDate(purchaseDate)})';
    }
    return null;
  }

  /// `5 Mar 2024` — the date style used for transactions.
  static String formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  static double _scale(double holding) => holding.abs() > 1 ? holding.abs() : 1;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
}
