import '../data/models/asset_type.dart';

/// Result of a price fetch operation
class PriceResult {
  final String symbol;
  final double price;
  final String currency;
  final DateTime fetchedAt;
  final bool success;
  final String? error;

  const PriceResult({
    required this.symbol,
    required this.price,
    required this.currency,
    required this.fetchedAt,
    required this.success,
    this.error,
  });

  /// Create a failed result
  factory PriceResult.failure(String symbol, String error) {
    return PriceResult(
      symbol: symbol,
      price: 0,
      currency: '',
      fetchedAt: DateTime.now(),
      success: false,
      error: error,
    );
  }

  @override
  String toString() =>
      'PriceResult(symbol: $symbol, price: $price, success: $success)';
}

/// Abstract price service interface
abstract class PriceService {
  /// Fetch the current price for a given symbol
  Future<PriceResult> fetchPrice(String symbol);

  /// Check if this service supports the given asset type
  bool supportsAssetType(AssetType type);
}

/// Well-known symbols and helpers for price tracking
class PriceSymbols {
  PriceSymbols._();

  /// COMEX Gold futures (USD per troy oz) — international price.
  /// This is the single source of truth for gold prices.
  /// We convert to INR/gram locally using live forex + Indian taxes.
  static const String goldComex = 'GC=F';

  /// Bitcoin on CoinGecko
  static const String bitcoin = 'bitcoin';

  /// Ethereum on CoinGecko
  static const String ethereum = 'ethereum';

  /// Returns the gold tracking symbol.
  ///
  /// Always uses COMEX GC=F regardless of currency.
  /// Currency conversion (USD → INR, etc.) and Indian import duty/GST
  /// are applied locally by [GoldPriceService].
  static String goldSymbolForCurrency(String baseCurrency) {
    return goldComex;
  }

  /// Returns true if the given symbol is the COMEX gold futures symbol
  static bool isComexGold(String symbol) {
    return symbol == goldComex;
  }

  /// Returns the default symbol for auto-tracking (if none entered by user)
  static String? defaultSymbol(AssetType type, {String baseCurrency = 'INR'}) {
    switch (type) {
      case AssetType.gold:
        return goldComex;
      default:
        return null;
    }
  }

  /// Returns symbol input hint text for each asset type
  static String symbolHint(AssetType type, {String baseCurrency = 'INR'}) {
    switch (type) {
      case AssetType.stock:
        return 'e.g. RELIANCE.NS, AAPL, TCS.NS';
      case AssetType.mutualFund:
        return 'e.g. NIFTY50.NS (ETF proxy)';
      case AssetType.crypto:
        return 'e.g. bitcoin, ethereum, solana';
      case AssetType.gold:
        return 'GC=F (COMEX, auto-filled — converts to INR with taxes)';
      case AssetType.bond:
        return 'e.g. bond ticker (optional)';
      case AssetType.fixedDeposit:
      case AssetType.cash:
      case AssetType.realEstate:
        return 'Not applicable — manual price only';
    }
  }

  /// Returns true if auto price tracking is supported for the given asset type
  static bool supportsAutoTracking(AssetType type) {
    switch (type) {
      case AssetType.stock:
      case AssetType.mutualFund:
      case AssetType.gold:
      case AssetType.crypto:
        return true;
      case AssetType.bond:
      case AssetType.fixedDeposit:
      case AssetType.cash:
      case AssetType.realEstate:
        return false;
    }
  }
}
