import 'package:flutter/material.dart';

/// KashU App Colors - Dark Minimal Theme
class AppColors {
  AppColors._();

  // Primary Colors
  static const Color primary = Color(0xFF6C63FF);
  static const Color primaryLight = Color(0xFF8B85FF);
  static const Color primaryDark = Color(0xFF4B44B3);

  // Background Colors
  static const Color background = Color(0xFF0D0D0D);
  static const Color backgroundLight = Color(0xFF1A1A1A);
  static const Color surface = Color(0xFF1E1E1E);
  static const Color surfaceLight = Color(0xFF2A2A2A);
  static const Color card = Color(0xFF242424);

  // Text Colors
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0B0B0);
  static const Color textTertiary = Color(0xFF707070);
  static const Color textHint = Color(0xFF505050);

  // Accent Colors
  static const Color success = Color(0xFF00C853);
  static const Color successLight = Color(0xFF69F0AE);
  static const Color error = Color(0xFFFF5252);
  static const Color errorLight = Color(0xFFFF8A80);
  static const Color warning = Color(0xFFFFD600);
  static const Color info = Color(0xFF448AFF);

  // Asset Type Colors
  static const Color stockColor = Color(0xFF6C63FF);
  static const Color mutualFundColor = Color(0xFF00BCD4);
  static const Color goldColor = Color(0xFFFFD700);
  static const Color cryptoColor = Color(0xFFF7931A);
  static const Color bondColor = Color(0xFF4CAF50);
  static const Color fdColor = Color(0xFF9C27B0);
  static const Color cashColor = Color(0xFF607D8B);
  static const Color realEstateColor = Color(0xFF795548);

  // Chart Colors
  static const List<Color> chartColors = [
    stockColor,
    mutualFundColor,
    goldColor,
    cryptoColor,
    bondColor,
    fdColor,
    cashColor,
    realEstateColor,
  ];

  // Gradient
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [surface, surfaceLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Divider
  static const Color divider = Color(0xFF2A2A2A);
  static const Color border = Color(0xFF333333);

  // Shimmer
  static const Color shimmerBase = Color(0xFF1E1E1E);
  static const Color shimmerHighlight = Color(0xFF2A2A2A);
}
