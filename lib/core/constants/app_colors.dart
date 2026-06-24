import 'package:flutter/material.dart';

/// KashU App Colors — "C · Soft" direction (calm soft-pop).
///
/// Gentle depth, candy pastels, indigo→lavender brand. The semantic tokens
/// below (background/surface/text/...) hold the **dark** values so the rest of
/// the app keeps working while screens are migrated one by one. Light values
/// live under the `light*` tokens and feed [AppTheme.lightTheme].
class AppColors {
  AppColors._();

  // ── Brand (mode-independent) ────────────────────────────────────────────
  static const Color primary = Color(0xFF6366F1); // indigo
  static const Color primaryLight = Color(0xFFA78BFA); // lavender
  static const Color primaryDark = Color(0xFF4F46E5);

  /// Indigo → lavender, the signature card/button gradient.
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF6366F1), Color(0xFFA78BFA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Three-stop hero gradient used on the portfolio value card.
  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF6366F1), Color(0xFF8B7CF0), Color(0xFFA78BFA)],
    stops: [0.0, 0.6, 1.0],
    begin: Alignment(-0.8, -1),
    end: Alignment(0.8, 1),
  );

  /// Mint gradient — the floating action button & positive accents.
  static const LinearGradient mintGradient = LinearGradient(
    colors: [Color(0xFF34D399), Color(0xFF10B981)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Dark palette (active) ───────────────────────────────────────────────
  static const Color background = Color(0xFF15131F);
  static const Color backgroundLight = Color(0xFF1B1828);
  static const Color surface = Color(0xFF211E2E);
  static const Color surfaceLight = Color(0xFF2A2738);
  static const Color card = Color(0xFF211E2E);

  static const Color textPrimary = Color(0xFFF3F1FB);
  static const Color textSecondary = Color(0xFF9A95AD);
  static const Color textTertiary = Color(0xFF6B6680);
  static const Color textHint = Color(0xFF4A4658);

  static const Color divider = Color(0xFF2C2A3A);
  static const Color border = Color(0xFF35324A);

  // ── Light palette (feeds AppTheme.lightTheme) ───────────────────────────
  static const Color lightBackground = Color(0xFFF1F0FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFF6F5FC);
  static const Color lightTextPrimary = Color(0xFF221F2E);
  static const Color lightTextSecondary = Color(0xFF8C8799);
  static const Color lightTextTertiary = Color(0xFFB3AEC4);
  static const Color lightDivider = Color(0xFFE9E7F4);

  /// Soft purple-tinted shadow used across cards in both modes.
  static const Color softShadow = Color(0xFF50468C);

  // ── Gain / loss (semantic) ──────────────────────────────────────────────
  static const Color success = Color(0xFF34D399);
  static const Color successLight = Color(0xFF4ADE80);
  static const Color error = Color(0xFFF87171);
  static const Color errorLight = Color(0xFFFCA5A5);
  static const Color warning = Color(0xFFFBBF24);
  static const Color info = Color(0xFF38BDF8);

  /// Gain/loss tuned for light surfaces (stronger contrast on white).
  static const Color gainLight = Color(0xFF16A34A);
  static const Color lossLight = Color(0xFFEF4444);

  // ── Asset type tones (candy pastels) ────────────────────────────────────
  static const Color stockColor = Color(0xFF34D399); // mint
  static const Color mutualFundColor = Color(0xFF6366F1); // indigo
  static const Color goldColor = Color(0xFFFB923C); // orange
  static const Color cryptoColor = Color(0xFFF472B6); // pink
  static const Color bondColor = Color(0xFF22D3EE); // cyan
  static const Color fdColor = Color(0xFFA78BFA); // lavender
  static const Color cashColor = Color(0xFF38BDF8); // sky
  static const Color realEstateColor = Color(0xFFFBBF24); // amber

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

  static const LinearGradient cardGradient = LinearGradient(
    colors: [surface, surfaceLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Shimmer ─────────────────────────────────────────────────────────────
  static const Color shimmerBase = Color(0xFF2A2738);
  static const Color shimmerHighlight = Color(0xFF35324A);

  // ── Brightness-aware helpers ────────────────────────────────────────────
  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color textPrimaryOn(BuildContext context) =>
      _isDark(context) ? textPrimary : lightTextPrimary;

  static Color textSecondaryOn(BuildContext context) =>
      _isDark(context) ? textSecondary : lightTextSecondary;

  static Color textTertiaryOn(BuildContext context) =>
      _isDark(context) ? textTertiary : lightTextTertiary;

  /// Gain/loss colour tuned to the current surface brightness.
  static Color gainOn(BuildContext context) =>
      _isDark(context) ? successLight : gainLight;

  static Color lossOn(BuildContext context) =>
      _isDark(context) ? error : lossLight;
}
