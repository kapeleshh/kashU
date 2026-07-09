import 'package:intl/intl.dart';
import '../constants/app_constants.dart';

/// Utility class for formatting currency values
class CurrencyFormatter {
  CurrencyFormatter._();

  /// Format amount in INR
  static String formatINR(double amount, {bool showSymbol = true}) {
    final formatter = NumberFormat.currency(
      locale: 'en_IN',
      symbol: showSymbol ? '₹' : '',
      decimalDigits: 2,
    );
    return formatter.format(amount);
  }

  /// Format amount with compact notation (e.g., 1.2L, 10Cr)
  static String formatCompactINR(double amount) {
    if (amount >= 10000000) {
      return '₹${(amount / 10000000).toStringAsFixed(2)}Cr';
    } else if (amount >= 100000) {
      return '₹${(amount / 100000).toStringAsFixed(2)}L';
    } else if (amount >= 1000) {
      return '₹${(amount / 1000).toStringAsFixed(2)}K';
    }
    return formatINR(amount);
  }

  /// Format percentage
  static String formatPercentage(double percentage, {bool showSign = true}) {
    final sign = showSign && percentage > 0 ? '+' : '';
    return '$sign${percentage.toStringAsFixed(2)}%';
  }

  /// Format amount in any currency
  static String formatCurrency(double amount, String currency) {
    final symbol = AppConstants.currencies[currency] ?? currency;
    final formatter = NumberFormat.currency(
      symbol: symbol,
      decimalDigits: 2,
    );
    return formatter.format(amount);
  }

  /// Compact notation for any currency (e.g. ₹1.2L, $10K).
  ///
  /// INR uses the Indian Cr/L/K scale (like [formatCompactINR]); other
  /// currencies use K/M/B. Values below 1000 fall back to [formatCurrency].
  static String formatCompactCurrency(double amount, String currency) {
    final symbol = AppConstants.currencies[currency] ?? currency;
    final sign = amount < 0 ? '-' : '';
    final n = amount.abs();

    if (currency == 'INR') {
      if (n >= 10000000) return '$sign$symbol${(n / 10000000).toStringAsFixed(2)}Cr';
      if (n >= 100000) return '$sign$symbol${(n / 100000).toStringAsFixed(2)}L';
      if (n >= 1000) return '$sign$symbol${(n / 1000).toStringAsFixed(2)}K';
      return formatCurrency(amount, currency);
    }

    if (n >= 1000000000) return '$sign$symbol${(n / 1000000000).toStringAsFixed(2)}B';
    if (n >= 1000000) return '$sign$symbol${(n / 1000000).toStringAsFixed(2)}M';
    if (n >= 1000) return '$sign$symbol${(n / 1000).toStringAsFixed(2)}K';
    return formatCurrency(amount, currency);
  }

  /// Format quantity (for stocks, crypto, etc.)
  static String formatQuantity(double quantity) {
    if (quantity == quantity.truncate()) {
      return quantity.truncate().toString();
    }
    return quantity.toStringAsFixed(4).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  /// Convert amount to INR using exchange rate
  static double convertToINR(double amount, String fromCurrency) {
    final rate = AppConstants.defaultExchangeRates[fromCurrency] ?? 1.0;
    return amount * rate;
  }
}
