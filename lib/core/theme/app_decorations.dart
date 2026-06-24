import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Shared "C · Soft" decorations: gentle radii, soft purple-tinted shadows and
/// the pastel gradients used for asset/category avatars.
class AppRadii {
  AppRadii._();

  static const double card = 22;
  static const double hero = 26;
  static const double tile = 18;
  static const double small = 16;
  static const double pill = 20;
  static const double nav = 24;
  static const double avatar = 14;
}

class AppShadows {
  AppShadows._();

  /// Soft drop shadow for raised cards (negative spread → diffuse halo).
  static List<BoxShadow> soft({double opacity = 0.20, double y = 12, double blur = 28}) =>
      [
        BoxShadow(
          color: AppColors.softShadow.withValues(alpha: opacity),
          blurRadius: blur,
          offset: Offset(0, y),
          spreadRadius: -10,
        ),
      ];

  /// Stronger glow tinted to a brand colour (hero card, FAB, gradient pills).
  static List<BoxShadow> glow(Color color, {double opacity = 0.55}) => [
        BoxShadow(
          color: color.withValues(alpha: opacity),
          blurRadius: 26,
          offset: const Offset(0, 14),
          spreadRadius: -12,
        ),
      ];
}

/// Pastel gradient for a small rounded avatar tile, keyed off a base tone.
LinearGradient softAvatarGradient(Color base) {
  return LinearGradient(
    colors: [base, Color.lerp(base, Colors.white, 0.28)!],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
