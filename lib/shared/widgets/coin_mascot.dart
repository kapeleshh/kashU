import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// The KashU coin-buddy — a small gentle-bobbing gold coin with a ₹ and a
/// friendly face. Pure-Flutter (no assets), used in the dashboard header.
class CoinMascot extends StatefulWidget {
  final double size;
  const CoinMascot({super.key, this.size = 44});

  @override
  State<CoinMascot> createState() => _CoinMascotState();
}

class _CoinMascotState extends State<CoinMascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, -5 * _c.value),
        child: child,
      ),
      child: SizedBox(
        width: s,
        height: s,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // coin body
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  center: Alignment(-0.3, -0.4),
                  radius: 0.95,
                  colors: [Color(0xFFFCD34D), Color(0xFFF59E0B)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.55),
                    blurRadius: 16,
                    offset: const Offset(0, 9),
                    spreadRadius: -6,
                  ),
                ],
              ),
            ),
            // ₹ mark
            Positioned(
              top: s * 0.13,
              child: Text(
                '₹',
                style: AppTheme.heading(
                  size: s * 0.21,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ),
            // eyes
            Positioned(
              top: s * 0.45,
              left: s * 0.27,
              child: _eye(s),
            ),
            Positioned(
              top: s * 0.45,
              right: s * 0.27,
              child: _eye(s),
            ),
            // smile
            Positioned(
              top: s * 0.62,
              child: Container(
                width: s * 0.30,
                height: s * 0.14,
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Color(0xFF6B4A08), width: 2.2),
                    left: BorderSide(color: Color(0xFF6B4A08), width: 2.2),
                    right: BorderSide(color: Color(0xFF6B4A08), width: 2.2),
                  ),
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(11)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _eye(double s) => Container(
        width: s * 0.13,
        height: s * 0.18,
        decoration: const BoxDecoration(
          color: Color(0xFF6B4A08),
          borderRadius: BorderRadius.all(Radius.elliptical(6, 8)),
        ),
      );
}
