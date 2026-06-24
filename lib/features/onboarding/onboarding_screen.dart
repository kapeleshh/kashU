import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_theme.dart';
import '../dashboard/dashboard_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const _pages = [_WelcomePage(), _FeaturesPage(), _PrivacyPage()];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    await Hive.box(AppConstants.settingsBox)
        .put(AppConstants.keyOnboardingComplete, true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLastPage = _currentPage == _pages.length - 1;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextButton(
                  onPressed: _finish,
                  child: Text(
                    'Skip',
                    style: AppTheme.body(
                      size: 14,
                      weight: FontWeight.w700,
                      color: AppColors.textSecondaryOn(context),
                    ),
                  ),
                ),
              ),
            ),

            // Page content
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: _pages,
              ),
            ),

            // Dots + button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Column(
                children: [
                  // Page indicator dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_pages.length, (i) {
                      final active = i == _currentPage;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 26 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          gradient: active ? AppColors.primaryGradient : null,
                          color: active
                              ? null
                              : AppColors.textTertiaryOn(context)
                                  .withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),
                  // CTA button — full-width indigo→lavender gradient
                  _GradientCtaButton(
                    label: isLastPage ? 'Get Started' : 'Next',
                    onPressed: _nextPage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-width indigo→lavender gradient call-to-action button.
class _GradientCtaButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _GradientCtaButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(AppRadii.tile),
        boxShadow: AppShadows.glow(AppColors.primary, opacity: 0.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadii.tile),
          child: Container(
            width: double.infinity,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 17),
            child: Text(
              label,
              style: AppTheme.heading(
                size: 16,
                weight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Page 1: Welcome ─────────────────────────────────────────────────────────

class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Logo — brand gradient badge with soft glow
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              gradient: AppColors.heroGradient,
              borderRadius: BorderRadius.circular(AppRadii.hero),
              boxShadow: AppShadows.glow(AppColors.primary, opacity: 0.55),
            ),
            child: Center(
              child: Text(
                'K',
                style: AppTheme.heading(
                  size: 52,
                  weight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
          Text(
            'Welcome to ${AppStrings.appName}',
            style: AppTheme.heading(
              size: 26,
              weight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Text(
            AppStrings.appTagline,
            style: AppTheme.body(
              size: 17,
              weight: FontWeight.w600,
              color: AppColors.textSecondaryOn(context),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 22),
          Text(
            'Track all your investments — stocks, mutual funds, gold, crypto and more — in one clean dashboard.',
            style: AppTheme.body(
              size: 15,
              weight: FontWeight.w500,
              color: AppColors.textTertiaryOn(context),
            ).copyWith(height: 1.6),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Page 2: Features ────────────────────────────────────────────────────────

class _FeaturesPage extends StatelessWidget {
  const _FeaturesPage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Everything in one place',
            style: AppTheme.heading(
              size: 22,
              weight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Live prices, allocation charts, and performance at a glance.',
            style: AppTheme.body(
              size: 15,
              weight: FontWeight.w500,
              color: AppColors.textSecondaryOn(context),
            ),
          ),
          const SizedBox(height: 36),
          ..._features.map((f) => _FeatureTile(
                icon: f.$1,
                color: f.$2,
                title: f.$3,
                subtitle: f.$4,
              )),
        ],
      ),
    );
  }

  static const _features = [
    (
      Icons.show_chart,
      AppColors.stockColor,
      'Stocks & Mutual Funds',
      'NSE, BSE, NASDAQ — live prices via Yahoo Finance',
    ),
    (
      Icons.diamond,
      AppColors.goldColor,
      'Gold & Silver',
      'COMEX prices with Indian import duty + GST applied',
    ),
    (
      Icons.currency_bitcoin,
      AppColors.cryptoColor,
      'Cryptocurrency',
      '10,000+ coins via CoinGecko, no API key needed',
    ),
    (
      Icons.savings,
      AppColors.fdColor,
      'FDs, Bonds & More',
      'Track deposits with compound interest calculator',
    ),
  ];
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const _FeatureTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          // Asset-tone gradient avatar badge
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: softAvatarGradient(color),
              borderRadius: BorderRadius.circular(AppRadii.avatar),
              boxShadow: AppShadows.glow(color, opacity: 0.35),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.body(
                    size: 15,
                    weight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: AppTheme.body(
                    size: 13,
                    weight: FontWeight.w500,
                    color: AppColors.textTertiaryOn(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Page 3: Privacy ─────────────────────────────────────────────────────────

class _PrivacyPage extends StatelessWidget {
  const _PrivacyPage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Mint gradient privacy/lock badge
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              gradient: AppColors.mintGradient,
              borderRadius: BorderRadius.circular(AppRadii.hero),
              boxShadow: AppShadows.glow(AppColors.success, opacity: 0.45),
            ),
            child: const Icon(
              Icons.lock_outline,
              color: Colors.white,
              size: 44,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Your data stays on your device',
            style: AppTheme.heading(
              size: 22,
              weight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Text(
            'KashU is 100% offline-first. Your portfolio data never leaves your phone.',
            style: AppTheme.body(
              size: 15,
              weight: FontWeight.w500,
              color: AppColors.textSecondaryOn(context),
            ).copyWith(height: 1.6),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          // Soft surface card grouping the privacy points
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadii.card),
              boxShadow: AppShadows.soft(opacity: 0.16, y: 10, blur: 24),
            ),
            child: Column(
              children: _privacyPoints
                  .map((point) => _PrivacyPoint(icon: point.$1, text: point.$2))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  static const _privacyPoints = [
    (Icons.no_accounts_outlined, 'No account or login required'),
    (Icons.cloud_off_outlined, 'No data sent to any server'),
    (Icons.enhanced_encryption_outlined, 'All data encrypted on device'),
    (Icons.file_download_outlined, 'Export & backup at any time'),
  ];
}

class _PrivacyPoint extends StatelessWidget {
  final IconData icon;
  final String text;

  const _PrivacyPoint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          // Tonal mint icon chip
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadii.avatar),
            ),
            child: Icon(
              icon,
              color: AppColors.gainOn(context),
              size: 18,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: AppTheme.body(
                size: 14.5,
                weight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
