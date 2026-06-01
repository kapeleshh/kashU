import 'package:flutter/material.dart';

/// Money-themed 'K' logo used across the app.
/// Green gradient background with a gold ₹ accent conveys the financial theme.
class AppLogo extends StatelessWidget {
  final double size;

  const AppLogo({super.key, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.278;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E7B3A), Color(0xFF0F4D22)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: const Color(0xFFFFD700).withValues(alpha: 0.55),
          width: (size * 0.036).clamp(1.0, 2.5),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E7B3A).withValues(alpha: 0.55),
            blurRadius: size * 0.7,
            offset: Offset(0, size * 0.14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Center(
            child: Text(
              'K',
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.52,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                height: 1,
              ),
            ),
          ),
          Positioned(
            bottom: size * 0.07,
            right: size * 0.07,
            child: Text(
              '₹',
              style: TextStyle(
                color: const Color(0xFFFFD700),
                fontSize: size * 0.22,
                fontWeight: FontWeight.bold,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
