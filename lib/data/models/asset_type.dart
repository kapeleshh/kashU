import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';

part 'asset_type.g.dart';

/// Enum representing different asset types in the portfolio
@HiveType(typeId: 0)
enum AssetType {
  @HiveField(0)
  stock,
  
  @HiveField(1)
  mutualFund,
  
  @HiveField(2)
  gold,
  
  @HiveField(3)
  crypto,
  
  @HiveField(4)
  bond,
  
  @HiveField(5)
  fixedDeposit,
  
  @HiveField(6)
  cash,
  
  @HiveField(7)
  realEstate,
}

/// Extension to provide display name and icon for each asset type
extension AssetTypeExtension on AssetType {
  String get displayName {
    switch (this) {
      case AssetType.stock:
        return AppStrings.stocks;
      case AssetType.mutualFund:
        return AppStrings.mutualFunds;
      case AssetType.gold:
        return AppStrings.gold;
      case AssetType.crypto:
        return AppStrings.crypto;
      case AssetType.bond:
        return AppStrings.bonds;
      case AssetType.fixedDeposit:
        return AppStrings.fixedDeposits;
      case AssetType.cash:
        return AppStrings.cash;
      case AssetType.realEstate:
        return AppStrings.realEstate;
    }
  }

  IconData get icon {
    switch (this) {
      case AssetType.stock:
        return Icons.show_chart;
      case AssetType.mutualFund:
        return Icons.pie_chart;
      case AssetType.gold:
        return Icons.diamond;
      case AssetType.crypto:
        return Icons.currency_bitcoin;
      case AssetType.bond:
        return Icons.account_balance;
      case AssetType.fixedDeposit:
        return Icons.savings;
      case AssetType.cash:
        return Icons.account_balance_wallet;
      case AssetType.realEstate:
        return Icons.home;
    }
  }

  Color get color {
    switch (this) {
      case AssetType.stock:
        return AppColors.stockColor;
      case AssetType.mutualFund:
        return AppColors.mutualFundColor;
      case AssetType.gold:
        return AppColors.goldColor;
      case AssetType.crypto:
        return AppColors.cryptoColor;
      case AssetType.bond:
        return AppColors.bondColor;
      case AssetType.fixedDeposit:
        return AppColors.fdColor;
      case AssetType.cash:
        return AppColors.cashColor;
      case AssetType.realEstate:
        return AppColors.realEstateColor;
    }
  }

  /// Returns unit label for asset quantity
  String get unitLabel {
    switch (this) {
      case AssetType.stock:
      case AssetType.mutualFund:
        return 'units';
      case AssetType.gold:
        return 'grams';
      case AssetType.crypto:
        return 'coins';
      case AssetType.bond:
      case AssetType.fixedDeposit:
      case AssetType.cash:
      case AssetType.realEstate:
        return '';
    }
  }
}
