import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/portfolio_summary.dart';

/// The "Total worth" hero — an indigo→lavender gradient card with the live
/// portfolio value, today's move and the all-time return as soft pills.
class PortfolioSummaryCard extends StatelessWidget {
  final PortfolioSummary? summary;
  final bool isLoading;
  final String? errorMessage;

  const PortfolioSummaryCard({
    super.key,
    required this.summary,
  })  : isLoading = false,
        errorMessage = null;

  const PortfolioSummaryCard.loading({super.key})
      : summary = null,
        isLoading = true,
        errorMessage = null;

  const PortfolioSummaryCard.error(String error, {super.key})
      : summary = null,
        isLoading = false,
        errorMessage = error;

  @override
  Widget build(BuildContext context) {
    if (isLoading) return _buildLoadingCard(context);
    if (errorMessage != null) return _buildErrorCard(context);

    final data = summary ?? PortfolioSummary.empty();
    final isProfit = data.totalGainLoss >= 0;
    final todayUp = data.todaysChange >= 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(AppRadii.hero),
        boxShadow: AppShadows.glow(AppColors.primary, opacity: 0.5),
      ),
      child: Stack(
        children: [
          // decorative blobs
          Positioned(
            right: -28,
            top: -28,
            child: _blob(90, 0.12),
          ),
          Positioned(
            right: 24,
            bottom: -34,
            child: _blob(60, 0.10),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    AppStrings.totalPortfolioValue,
                    style: AppTheme.body(
                      size: 12,
                      weight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(width: 7),
                  const _LiveDot(),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                CurrencyFormatter.formatINR(data.totalValue),
                style: AppTheme.heading(size: 33, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  _pill(
                    '${todayUp ? '▲' : '▼'} ${CurrencyFormatter.formatINR(data.todaysChange.abs())} today',
                  ),
                  _pill(
                    '${isProfit ? '+' : '-'}${CurrencyFormatter.formatPercentage(data.totalGainLossPercentage.abs(), showSign: false)} all-time',
                  ),
                ],
              ),
              if (!data.isEmpty) ...[
                const SizedBox(height: 9),
                Text(
                  'Invested ${CurrencyFormatter.formatCompactINR(data.totalInvested)} · '
                  '${isProfit ? 'up' : 'down'} ${CurrencyFormatter.formatCompactINR(data.totalGainLoss.abs())}'
                  '${isProfit ? ' 🎉' : ''}',
                  style: AppTheme.body(
                    size: 11,
                    weight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
              ],
              if (data.isEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadii.small),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome,
                          color: Colors.white.withValues(alpha: 0.9), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          AppStrings.noAssets,
                          style: AppTheme.body(
                            size: 12.5,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _blob(double size, double opacity) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: opacity),
          shape: BoxShape.circle,
        ),
      );

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Text(
          text,
          style: AppTheme.body(
            size: 11.5,
            weight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      );

  Widget _buildLoadingCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.hero),
        boxShadow: AppShadows.soft(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _shimmer(140, 14),
          const SizedBox(height: 12),
          _shimmer(200, 34),
          const SizedBox(height: 16),
          Row(
            children: [
              _shimmer(110, 26),
              const SizedBox(width: 8),
              _shimmer(110, 26),
            ],
          ),
        ],
      ),
    );
  }

  Widget _shimmer(double width, double height) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.shimmerBase,
          borderRadius: BorderRadius.circular(8),
        ),
      );

  Widget _buildErrorCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.hero),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              errorMessage ?? AppStrings.errorGeneric,
              style: AppTheme.body(
                size: 13,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small pulsing "live" indicator dot.
class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.35).animate(_c),
      child: ScaleTransition(
        scale: Tween(begin: 1.0, end: 0.65).animate(_c),
        child: Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: Color(0xFFD7FBE8),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
