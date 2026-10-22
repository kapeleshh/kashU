import '../data/models/asset.dart';
import 'currency_converter_service.dart';

/// Converts amounts kept in each holding's own currency into the user's base
/// currency: the one rates path behind every portfolio total.
///
/// The dashboard (`portfolioSummaryProvider`), the rebalancing screen (which
/// reads that summary) and the capital-gains PDF all total through this, so a
/// USD holding in an INR portfolio is worth the same everywhere instead of
/// being added up as if its dollars were rupees.
class BaseCurrencyConverter {
  /// The currency every converted amount is expressed in.
  final String base;

  /// Live rates, or null when no holding needed converting. A missing
  /// currency (or a null [rates] met with a foreign amount anyway) falls back
  /// to the approximate static rates, never to the unconverted figure.
  final ExchangeRateResult? rates;

  const BaseCurrencyConverter({required this.base, this.rates});

  static final ExchangeRateResult _offline =
      ExchangeRateResult.failure('No live exchange rates');

  /// A converter for amounts in [currencies], into [base]. Offline-first:
  /// [loadRates] is only called when one of them is actually another
  /// currency, so an all-base portfolio never blocks on (or requires) a
  /// forex fetch.
  static Future<BaseCurrencyConverter> forCurrencies(
    Iterable<String> currencies, {
    required String base,
    required Future<ExchangeRateResult> Function() loadRates,
  }) async {
    final needsRates = currencies.any((c) => c.isNotEmpty && c != base);
    return BaseCurrencyConverter(
      base: base,
      rates: needsRates ? await loadRates() : null,
    );
  }

  /// A converter for the holdings [assets], into [base] (see
  /// [forCurrencies]).
  static Future<BaseCurrencyConverter> forAssets(
    Iterable<Asset> assets, {
    required String base,
    required Future<ExchangeRateResult> Function() loadRates,
  }) =>
      forCurrencies(assets.map((a) => a.currency),
          base: base, loadRates: loadRates);

  /// The currency [asset]'s amounts are in (an empty one means [base]).
  String currencyOf(Asset asset) =>
      asset.currency.isNotEmpty ? asset.currency : base;

  /// [amount] in [currency], converted into [base].
  double convert(double amount, String currency) {
    final from = currency.isEmpty ? base : currency;
    if (from == base) return amount;
    return (rates ?? _offline).convertBetween(amount, from, base);
  }

  /// [asset]'s current value in [base].
  double valueOf(Asset asset) => convert(asset.currentValue, asset.currency);

  /// What was paid for [asset], in [base].
  double investedOf(Asset asset) =>
      convert(asset.totalInvested, asset.currency);

  /// True when at least one amount was converted with the approximate
  /// static rates because live ones were unavailable.
  bool get usedFallbackRates => rates != null && !rates!.success;
}
