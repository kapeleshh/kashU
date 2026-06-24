import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../dashboard/dashboard_screen.dart';

/// Full-screen lock screen shown at app startup when authentication is enabled.
///
/// Uses [AuthService] which delegates to the device's built-in auth
/// (biometrics or device PIN) — no in-app PIN setup required.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _authService = AuthService();
  bool _isAuthenticating = false;
  bool _notEnrolled = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Trigger auth prompt automatically on first open
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;
    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });

    final result = await _authService.authenticate(
      reason: 'Authenticate to open ${AppStrings.appName}',
    );

    if (!mounted) return;

    switch (result) {
      case AuthResult.success:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
      case AuthResult.notAvailable:
        // Device doesn't support auth — let them in anyway
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
      case AuthResult.notEnrolled:
        setState(() {
          _isAuthenticating = false;
          _notEnrolled = true;
          _errorMessage =
              'No biometrics or device PIN are set up. '
              'Go to your device Settings to add a PIN or fingerprint, '
              'or continue without lock protection.';
        });
      case AuthResult.cancelled:
        setState(() {
          _isAuthenticating = false;
          _errorMessage = null;
        });
      case AuthResult.failure:
        setState(() {
          _errorMessage = 'Authentication failed. Tap to try again.';
          _isAuthenticating = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Brand badge — indigo→lavender gradient with the K mark.
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(AppRadii.hero),
                    boxShadow: AppShadows.glow(AppColors.primary, opacity: 0.5),
                  ),
                  child: Center(
                    child: Text(
                      'K',
                      style: AppTheme.heading(
                        size: 46,
                        color: Colors.white,
                        weight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                Text(
                  AppStrings.appName,
                  style: AppTheme.heading(
                    size: 28,
                    color: theme.colorScheme.onSurface,
                    weight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  'Unlock to continue',
                  style: AppTheme.body(
                    size: 15,
                    weight: FontWeight.w500,
                    color: AppColors.textSecondaryOn(context),
                  ),
                ),

                const SizedBox(height: 48),

                if (_isAuthenticating)
                  const CircularProgressIndicator(color: AppColors.primary)
                else
                  _UnlockButton(onTap: _authenticate),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadii.small),
                      border: Border.all(
                        color: theme.colorScheme.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: AppTheme.body(
                        size: 13,
                        weight: FontWeight.w600,
                        color: theme.colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (_notEnrolled) ...[
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                            builder: (_) => const DashboardScreen()),
                      ),
                      child: const Text('Continue without lock'),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Soft, on-brand unlock affordance: a gradient fingerprint badge with a
/// gentle glow plus a helper label below.
class _UnlockButton extends StatelessWidget {
  final VoidCallback onTap;
  const _UnlockButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              shape: BoxShape.circle,
              boxShadow: AppShadows.glow(AppColors.primary, opacity: 0.45),
            ),
            child: const Icon(
              Icons.fingerprint,
              size: 40,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Tap to authenticate',
            style: AppTheme.body(
              size: 14,
              weight: FontWeight.w600,
              color: AppColors.textSecondaryOn(context),
            ),
          ),
        ],
      ),
    );
  }
}
