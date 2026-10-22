import 'package:kashu/data/models/asset.dart';
import 'package:kashu/data/models/asset_type.dart';
import 'package:kashu/services/currency_converter_service.dart';

/// The release-build sample portfolio the currency bug was reproduced with:
/// eleven INR holdings plus 8 Apple shares held in USD.
///
/// At [usdInr] = 85, the portfolio is worth ₹21,21,753.60, of which the
/// stocks (Apple included, at ₹1,56,400) are ₹4,03,900 (19.04%). Added up
/// without converting, Apple's $1,840 counted as ₹1,840 instead.
const double usdInr = 85;

/// Live-looking rates with USD→INR at [usdInr].
ExchangeRateResult sampleRates() => ExchangeRateResult(
      base: 'USD',
      rates: const {'USD': 1, 'INR': usdInr},
      fetchedAt: DateTime(2026, 10, 21),
      success: true,
    );

/// Expected totals in INR at [usdInr].
const double sampleTotalValueInr = 2121753.6;
const double sampleStockValueInr = 98000 + 90000 + 59500 + 8 * 230 * usdInr;

Asset _a(
  String id,
  String name,
  String? symbol,
  AssetType type,
  double qty,
  double buy,
  double cur, {
  String currency = 'INR',
}) {
  final at = DateTime(2024, 3, 1);
  return Asset(
    id: id,
    name: name,
    symbol: symbol,
    type: type,
    quantity: qty,
    purchasePrice: buy,
    currentPrice: cur,
    currency: currency,
    purchaseDate: at,
    createdAt: at,
    updatedAt: at,
  );
}

List<Asset> samplePortfolio() => [
      _a('reliance', 'Reliance Industries', 'RELIANCE.NS', AssetType.stock,
          40, 2350, 2450),
      _a('infy', 'Infosys', 'INFY.NS', AssetType.stock, 60, 1420, 1500),
      _a('hdfc', 'HDFC Bank', 'HDFCBANK.NS', AssetType.stock, 35, 1580, 1700),
      _a('aapl', 'Apple Inc.', 'AAPL', AssetType.stock, 8, 172.5, 230,
          currency: 'USD'),
      _a('ppfas', 'Parag Parikh Flexi Cap Fund - Direct Growth', '122639',
          AssetType.mutualFund, 1250.42, 58.3, 80),
      _a('uti', 'UTI Nifty 50 Index Fund - Direct Growth', '120716',
          AssetType.mutualFund, 1800.75, 128.4, 160),
      _a('gold', 'Gold, 24K coins', 'GC=F', AssetType.gold, 25, 6100, 12000),
      _a('silver', 'Silver, 999 bars', 'SI=F', AssetType.gold, 400, 78, 150),
      _a('btc', 'Bitcoin', 'bitcoin', AssetType.crypto, 0.042, 2850000,
          9000000),
      _a('eth', 'Ethereum', 'ethereum', AssetType.crypto, 0.65, 195000,
          350000),
      _a('fd', 'SBI Fixed Deposit, 7.1%', null, AssetType.fixedDeposit, 1,
          200000, 214200),
      _a('cash', 'Emergency fund', null, AssetType.cash, 1, 150000, 150000),
    ];
