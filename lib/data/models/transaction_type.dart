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

  /// Returns true if the transaction adds money/units to portfolio
  bool get isInflow {
    switch (this) {
      case TransactionType.buy:
        return true;
      case TransactionType.sell:
        return false;
      case TransactionType.dividend:
      case TransactionType.interest:
        return true; // Income transactions
    }
  }
}
