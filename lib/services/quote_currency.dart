import '../core/constants/app_constants.dart';
import 'currency_converter_service.dart';

/// Rules for fitting a fetched price quote onto a holding's currency.
///
/// A holding is stored in its own currency and only converted for display,
/// so a price must always be written in that currency. Quotes arrive in the
/// listing's currency — USD for AAPL, INR for RELIANCE.NS, and pence (GBp)
/// for London — which is how an AAPL autofill used to land a USD figure in
/// an INR field.
abstract final class QuoteCurrency {
  /// Minor-unit currency codes some exchanges quote in, mapped to the major
  /// currency and the divisor that gets there (LSE pence, JSE cents, TASE
  /// agorot). Case matters: Yahoo spells pence `GBp`, distinct from `GBP`.
  static const Map<String, (String, double)> _minorUnits = {
    'GBp': ('GBP', 100),
    'GBX': ('GBP', 100),
    'ZAc': ('ZAR', 100),
    'ILA': ('ILS', 100),
  };

  /// [price] in [currency], moved out of minor units when quoted in them.
  static ({double price, String currency}) normalize(
      double price, String currency) {
    final minor = _minorUnits[currency];
    if (minor != null) return (price: price / minor.$2, currency: minor.$1);
    return (price: price, currency: currency.toUpperCase());
  }

  /// Whether [currency] can be chosen in the app's currency field.
  static bool isSupported(String currency) =>
      AppConstants.currencies.containsKey(currency);

  /// [price] quoted in [quoteCurrency], expressed in [targetCurrency] — or
  /// null when that cannot be done honestly: the quote has no currency, or
  /// [rates] is missing, failed, or lacks a live rate for either side.
  /// Never guesses with an approximate rate; a wrong number written as a
  /// price is worse than asking for one.
  static double? convert(
    double price,
    String quoteCurrency,
    String targetCurrency,
    ExchangeRateResult? rates,
  ) {
    if (quoteCurrency.isEmpty) return null;
    final quote = normalize(price, quoteCurrency);
    if (quote.currency == targetCurrency) return quote.price;
    if (rates == null || !rates.success) return null;
    bool hasRate(String c) => c == rates.base || rates.rates.containsKey(c);
    if (!hasRate(quote.currency) || !hasRate(targetCurrency)) return null;
    return rates.convertBetween(quote.price, quote.currency, targetCurrency);
  }

  /// Decide how a fetched quote fills a form whose currency field holds
  /// [selectedCurrency].
  ///
  /// When the user has not picked a currency themselves, a quote in a
  /// supported currency moves the field to that currency and keeps the
  /// quoted price as is — no forex round trip, and the refresh later prices
  /// the holding in the same currency it was quoted in. Otherwise (the user
  /// chose the currency, or the quote's currency is not offered) the price
  /// is converted into [selectedCurrency] with [rates]. If that is not
  /// possible the plan asks for a manual price.
  static AutofillPlan plan({
    required double quotePrice,
    required String quoteCurrency,
    required String selectedCurrency,
    bool currencyChosenByUser = false,
    ExchangeRateResult? rates,
  }) {
    if (quoteCurrency.isEmpty) {
      return AutofillPlan._(
          AutofillAction.needsManualPrice, selectedCurrency, null);
    }
    final quote = normalize(quotePrice, quoteCurrency);
    if (quote.currency == selectedCurrency) {
      return AutofillPlan._(
          AutofillAction.asQuoted, selectedCurrency, quote.price);
    }
    if (!currencyChosenByUser && isSupported(quote.currency)) {
      return AutofillPlan._(
          AutofillAction.adoptQuoteCurrency, quote.currency, quote.price);
    }
    final converted =
        convert(quotePrice, quoteCurrency, selectedCurrency, rates);
    return converted == null
        ? AutofillPlan._(
            AutofillAction.needsManualPrice, selectedCurrency, null)
        : AutofillPlan._(
            AutofillAction.converted, selectedCurrency, converted);
  }
}

/// What [QuoteCurrency.plan] decided.
enum AutofillAction {
  /// The quote is already in the selected currency.
  asQuoted,

  /// Switch the currency field to the quote's currency; price as quoted.
  adoptQuoteCurrency,

  /// Keep the selected currency; the price was converted into it.
  converted,

  /// No honest conversion was possible — leave the price to the user.
  needsManualPrice,
}

class AutofillPlan {
  final AutofillAction action;

  /// The currency the form's currency field should hold.
  final String currency;

  /// The price in [currency]; null for [AutofillAction.needsManualPrice].
  final double? price;

  const AutofillPlan._(this.action, this.currency, this.price);

  @override
  String toString() => 'AutofillPlan($action, $currency, $price)';
}
