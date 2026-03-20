import 'currency_converter_service.dart';
import 'price_service.dart';
import 'yahoo_finance_service.dart';
import '../data/models/asset_type.dart';

/// Breakdown of how a gold price was computed.
/// Useful for showing the user where the final price came from.
class GoldPriceBreakdown {
  /// Raw international price in USD per troy oz (from COMEX GC=F)
  final double usdPerTroyOz;

  /// USD per gram (usdPerTroyOz / 31.1035)
  final double usdPerGram;

  /// Live USD → target currency exchange rate
  final double forexRate;

  /// Base price in target currency per gram (before any taxes)
  final double basePerGram;

  /// Import duty rate applied (e.g. 0.10 = 10%)
  final double importDutyRate;

  /// GST rate applied (e.g. 0.03 = 3%)
  final double gstRate;

  /// Agriculture Infrastructure & Development Cess (AIDC) rate (e.g. 0.05 = 5%)
  final double aidcRate;

  /// Total tax multiplier = (1 + importDutyRate + aidcRate) * (1 + gstRate)
  double get totalTaxMultiplier =>
      (1 + importDutyRate + aidcRate) * (1 + gstRate);

  /// Final price per gram after all taxes in target currency
  double get finalPerGram => basePerGram * totalTaxMultiplier;

  /// Amount added per gram due to all taxes
  double get taxAmountPerGram => finalPerGram - basePerGram;

  /// Effective total tax percentage on base price
  double get effectiveTaxPercent => (totalTaxMultiplier - 1) * 100;

  /// Target currency (e.g. 'INR')
  final String targetCurrency;

  /// Whether live forex rates were used (false = fallback approximate)
  final bool usedLiveForex;

  const GoldPriceBreakdown({
    required this.usdPerTroyOz,
    required this.usdPerGram,
    required this.forexRate,
    required this.basePerGram,
    required this.importDutyRate,
    required this.gstRate,
    required this.aidcRate,
    required this.targetCurrency,
    required this.usedLiveForex,
  });

  @override
  String toString() {
    return 'GoldPriceBreakdown(\n'
        '  COMEX: \$${usdPerTroyOz.toStringAsFixed(2)}/troy oz\n'
        '  USD/gram: \$${usdPerGram.toStringAsFixed(4)}\n'
        '  Forex: 1 USD = $forexRate $targetCurrency\n'
        '  Base: ${basePerGram.toStringAsFixed(2)} $targetCurrency/gram\n'
        '  Import Duty: ${(importDutyRate * 100).toStringAsFixed(1)}%\n'
        '  AIDC: ${(aidcRate * 100).toStringAsFixed(1)}%\n'
        '  GST: ${(gstRate * 100).toStringAsFixed(1)}%\n'
        '  Effective Tax: ${effectiveTaxPercent.toStringAsFixed(2)}%\n'
        '  Final: ${finalPerGram.toStringAsFixed(2)} $targetCurrency/gram\n'
        ')';
  }
}

/// Indian government taxes applied on gold at import/sale.
///
/// Updated to Union Budget 2024 (effective July 23, 2024) rates:
/// - Basic Customs Duty (BCD): 5%  (reduced from 10%)
/// - Agriculture Infrastructure & Development Cess (AIDC): 1%  (reduced from 5%)
/// - GST on gold jewellery/coins: 3%  (unchanged)
///
/// Combined effective rate ≈ 9.18% above the international price.
/// Formula: finalPrice = basePrice * (1 + BCD + AIDC) * (1 + GST)
class GoldTaxConfig {
  /// Basic Customs Duty on gold import (5% as of Budget 2024)
  final double importDutyRate;

  /// Agriculture Infrastructure & Development Cess (1% as of Budget 2024)
  final double aidcRate;

  /// GST rate on gold (3% — unchanged)
  final double gstRate;

  const GoldTaxConfig({
    this.importDutyRate = 0.05,
    this.aidcRate = 0.01,
    this.gstRate = 0.03,
  });

  /// Default Indian gold tax configuration (Budget 2024 rates)
  static const GoldTaxConfig india = GoldTaxConfig(
    importDutyRate: 0.05,
    aidcRate: 0.01,
    gstRate: 0.03,
  );

  /// No tax (for international / USD price without Indian duties)
  static const GoldTaxConfig none = GoldTaxConfig(
    importDutyRate: 0,
    aidcRate: 0,
    gstRate: 0,
  );

  double get totalTaxMultiplier => (1 + importDutyRate + aidcRate) * (1 + gstRate);

  double get effectiveTaxPercent => (totalTaxMultiplier - 1) * 100;

  @override
  String toString() =>
      'GoldTaxConfig(BCD=${(importDutyRate * 100).toStringAsFixed(0)}%,'
      ' AIDC=${(aidcRate * 100).toStringAsFixed(0)}%,'
      ' GST=${(gstRate * 100).toStringAsFixed(0)}%,'
      ' effective=${effectiveTaxPercent.toStringAsFixed(2)}%)';
}

/// Dedicated service for fetching the current gold price.
///
/// Strategy:
/// 1. Fetch COMEX GC=F (USD per troy oz) from Yahoo Finance — reliable & free.
/// 2. Convert: USD/troy oz → USD/gram (÷ 31.1035).
/// 3. Convert: USD/gram → target currency/gram using live forex rates.
/// 4. Apply Indian import duty + AIDC + GST for INR prices.
///
/// This replaces the fragile MCX (GOLDM.MCX) Yahoo Finance endpoint which
/// is often unavailable or returns stale data.
class GoldPriceService implements PriceService {
  final YahooFinanceService _yahooService;
  final CurrencyConverterService _currencyConverter;

  GoldPriceService({
    YahooFinanceService? yahooService,
    CurrencyConverterService? currencyConverter,
  })  : _yahooService = yahooService ?? YahooFinanceService(),
        _currencyConverter = currencyConverter ?? CurrencyConverterService();

  @override
  bool supportsAssetType(AssetType type) => type == AssetType.gold;

  /// Fetch gold price for the given [targetCurrency].
  ///
  /// Always fetches COMEX GC=F (USD/troy oz) and converts locally.
  /// For INR, automatically applies Indian import duty + AIDC + GST.
  ///
  /// Returns price in **targetCurrency per gram**.
  @override
  Future<PriceResult> fetchPrice(String symbol) async {
    // symbol is ignored — we always use GC=F
    return fetchGoldPrice();
  }

  /// Fetch gold price in USD per gram (no tax).
  Future<PriceResult> fetchGoldPrice({String targetCurrency = 'USD'}) async {
    final breakdown = await fetchGoldPriceBreakdown(
      targetCurrency: targetCurrency,
      taxConfig: targetCurrency == 'INR' ? GoldTaxConfig.india : GoldTaxConfig.none,
    );

    if (breakdown == null) {
      return PriceResult.failure(
        PriceSymbols.goldComex,
        'Could not fetch gold price from COMEX (GC=F)',
      );
    }

    return PriceResult(
      symbol: PriceSymbols.goldComex,
      price: breakdown.finalPerGram,
      currency: targetCurrency,
      fetchedAt: DateTime.now(),
      success: true,
    );
  }

  /// Fetch gold price with full breakdown (base + tax components).
  ///
  /// [targetCurrency] — the currency to convert into (e.g. 'INR', 'USD')
  /// [taxConfig]      — which taxes to apply (default: Indian duties for INR)
  ///
  /// Returns null if the COMEX price cannot be fetched.
  Future<GoldPriceBreakdown?> fetchGoldPriceBreakdown({
    String targetCurrency = 'INR',
    GoldTaxConfig? taxConfig,
  }) async {
    final effectiveTax = taxConfig ??
        (targetCurrency == 'INR' ? GoldTaxConfig.india : GoldTaxConfig.none);

    // Step 1: Fetch COMEX GC=F → USD per troy oz
    final comexResult = await _yahooService.fetchPrice(PriceSymbols.goldComex);
    if (!comexResult.success) return null;

    final usdPerTroyOz = comexResult.price;

    // Step 2: USD/troy oz → USD/gram
    final usdPerGram = usdPerTroyOz / CurrencyConverterService.gramsPerTroyOz;

    // Step 3: USD/gram → targetCurrency/gram via live forex
    bool usedLiveForex = false;
    double forexRate;
    double basePerGram;

    if (targetCurrency == 'USD') {
      forexRate = 1.0;
      basePerGram = usdPerGram;
      usedLiveForex = true;
    } else {
      final rates = await _currencyConverter.fetchRates();
      if (rates.success) {
        forexRate = rates.getRate(targetCurrency);
        usedLiveForex = true;
      } else {
        // Fallback to hardcoded approximate rate
        forexRate = CurrencyConverterService.fallbackRate(targetCurrency);
        usedLiveForex = false;
      }
      basePerGram = usdPerGram * forexRate;
    }

    return GoldPriceBreakdown(
      usdPerTroyOz: usdPerTroyOz,
      usdPerGram: usdPerGram,
      forexRate: forexRate,
      basePerGram: basePerGram,
      importDutyRate: effectiveTax.importDutyRate,
      aidcRate: effectiveTax.aidcRate,
      gstRate: effectiveTax.gstRate,
      targetCurrency: targetCurrency,
      usedLiveForex: usedLiveForex,
    );
  }
}
