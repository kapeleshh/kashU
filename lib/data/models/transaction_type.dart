import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';

part 'transaction_type.g.dart';

/// Enum representing different transaction types
@HiveType(typeId: 1)
enum TransactionType {
  @HiveField(0)
  buy,
  
  @HiveField(1)
  sell,
  
  @HiveField(2)
  dividend,
  
  @HiveField(3)
  interest,
}

/// Extension to provide display name, icon and color for each transaction type
extension TransactionTypeExtension on TransactionType {
  String get displayName {
    switch (this) {
      case TransactionType.buy:
        return AppStrings.buy;
      case TransactionType.sell:
        return AppStrings.sell;
      case TransactionType.dividend:
        return AppStrings.dividend;
      case TransactionType.interest:
        return AppStrings.interest;
    }
  }

  IconData get icon {
    switch (this) {
      case TransactionType.buy:
        return Icons.add_circle;
      case TransactionType.sell:
        return Icons.remove_circle;
      case TransactionType.dividend:
        return Icons.payments;
      case TransactionType.interest:
        return Icons.percent;
    }
  }

  Color get color {
    switch (this) {
      case TransactionType.buy:
        return AppColors.error; // Red for money going out
      case TransactionType.sell:
        return AppColors.success; // Green for money coming in
      case TransactionType.dividend:
        return AppColors.success;
      case TransactionType.interest:
        return AppColors.success;
    }
  }

  /// True when money comes *in* to the investor: a sale's proceeds, a
  /// dividend, interest. A buy is money going out. (Cash, not units — a buy
  /// adds units but is still an outflow.)
  bool get isCashInflow {
    switch (this) {
      case TransactionType.buy:
        return false;
      case TransactionType.sell:
      case TransactionType.dividend:
      case TransactionType.interest:
        return true;
    }
  }
}
