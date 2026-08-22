import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';
import 'app_decorations.dart';

/// KashU "C · Soft" theme — calm soft-pop. Quicksand for headings (display /
/// headline / title) and Plus Jakarta Sans for body & labels. Both a light and
/// a dark [ThemeData] are provided; the app currently runs dark while screens
/// are migrated.
class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme => _build(Brightness.dark);
  static ThemeData get lightTheme => _build(Brightness.light);

  /// Headings — Quicksand. Use for hero numbers, screen titles, card titles.
  static TextStyle heading(
          {required double size, Color? color, FontWeight weight = FontWeight.w700}) =>
      GoogleFonts.quicksand(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: 0.2,
      );

  /// Body / UI — Plus Jakarta Sans.
  static TextStyle body(
          {required double size, Color? color, FontWeight weight = FontWeight.w600}) =>
      GoogleFonts.plusJakartaSans(
        fontSize: size,
        fontWeight: weight,
        color: color,
      );

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final bg = isDark ? AppColors.background : AppColors.lightBackground;
    final surface = isDark ? AppColors.surface : AppColors.lightSurface;
    final onSurface = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
    final secondary =
        isDark ? AppColors.textSecondary : AppColors.lightTextSecondary;
    final tertiary =
        isDark ? AppColors.textTertiary : AppColors.lightTextTertiary;
    final divider = isDark ? AppColors.divider : AppColors.lightDivider;

    final textTheme = _textTheme(onSurface, secondary, tertiary);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      textTheme: textTheme,

      colorScheme: ColorScheme(
        brightness: brightness,
        primary: AppColors.primary,
        onPrimary: Colors.white,
        primaryContainer: AppColors.primaryDark,
        onPrimaryContainer: Colors.white,
        secondary: AppColors.primaryLight,
        onSecondary: Colors.white,
        surface: surface,
        onSurface: onSurface,
        surfaceContainerHighest:
            isDark ? AppColors.surfaceLight : AppColors.lightSurfaceAlt,
        error: isDark ? AppColors.error : AppColors.lossLight,
        onError: Colors.white,
        outline: divider,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent)
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent),
        titleTextStyle: AppTheme.heading(size: 20, color: onSurface),
      ),

      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        margin: const EdgeInsets.symmetric(vertical: 8),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: textTheme.bodyMedium?.copyWith(color: tertiary),
        labelStyle: textTheme.bodyMedium?.copyWith(color: secondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.small),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.small),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.small),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.small),
          borderSide: BorderSide(color: AppColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.small),
          borderSide: BorderSide(color: AppColors.error, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.tile),
          ),
          textStyle: AppTheme.heading(size: 16),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: AppTheme.body(size: 14, weight: FontWeight.w700),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.tile),
          ),
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: tertiary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      dividerTheme: DividerThemeData(color: divider, thickness: 1, space: 1),

      iconTheme: IconThemeData(color: secondary, size: 24),

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        iconColor: secondary,
        textColor: onSurface,
      ),

      chipTheme: ChipThemeData(
        backgroundColor:
            isDark ? AppColors.surfaceLight : AppColors.lightSurfaceAlt,
        labelStyle: textTheme.bodySmall?.copyWith(color: onSurface),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        titleTextStyle: AppTheme.heading(size: 18, color: onSurface),
        contentTextStyle: textTheme.bodyMedium,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? AppColors.surfaceLight : AppColors.lightTextPrimary,
        contentTextStyle: AppTheme.body(size: 14, color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.small),
        ),
      ),
    );
  }

  static TextTheme _textTheme(Color primary, Color secondary, Color tertiary) {
    TextStyle q(double s, FontWeight w, Color c) =>
        GoogleFonts.quicksand(fontSize: s, fontWeight: w, color: c, letterSpacing: 0.2);
    TextStyle j(double s, FontWeight w, Color c) =>
        GoogleFonts.plusJakartaSans(fontSize: s, fontWeight: w, color: c);

    return TextTheme(
      // Display & headline & title → Quicksand
      displayLarge: q(32, FontWeight.w700, primary),
      displayMedium: q(28, FontWeight.w700, primary),
      displaySmall: q(24, FontWeight.w700, primary),
      headlineLarge: q(22, FontWeight.w700, primary),
      headlineMedium: q(20, FontWeight.w700, primary),
      headlineSmall: q(18, FontWeight.w700, primary),
      titleLarge: q(16, FontWeight.w700, primary),
      titleMedium: j(14, FontWeight.w600, primary),
      titleSmall: j(12, FontWeight.w600, secondary),
      // Body & labels → Plus Jakarta Sans
      bodyLarge: j(16, FontWeight.w500, primary),
      bodyMedium: j(14, FontWeight.w500, primary),
      bodySmall: j(12, FontWeight.w500, secondary),
      labelLarge: j(14, FontWeight.w700, primary),
      labelMedium: j(12, FontWeight.w600, secondary),
      labelSmall: j(10, FontWeight.w600, tertiary),
    );
  }
}
