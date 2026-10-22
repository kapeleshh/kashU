import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../shared/providers/portfolio_provider.dart';
import '../../shared/widgets/kashu_logo.dart';

/// Full-screen lock shown while [appLockedProvider] is true — rendered as an
/// overlay above the app (see KashUApp's MaterialApp.builder), so unlocking
/// is a state change, not a navigation.
///
/// Uses [AuthService] which delegates to the device's built-in auth
/// (biometrics or device PIN) — no in-app PIN setup required.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  bool _isAuthenticating = false;

  /// True when the device cannot authenticate at all (no screen lock set up,
  /// or a platform error) — the only states that offer "Continue without
  /// lock", so a broken setup can never lock the user out of their data.
  /// Lock-outs from too many attempts deliberately don't qualify.
  bool _canBypass = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Trigger the auth prompt automatically when the lock appears. This only
    // runs on mount — the overlay stays mounted while locked, so a resume
    // can never fire a second prompt on top of an active one.
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  void _unlock() {
    ref.read(appLockedProvider.notifier).state = false;
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;
    setState(() {
      _isAuthenticating = true;
      _canBypass = false;
      _errorMessage = null;
    });

    final result = await ref.read(authServiceProvider).authenticate(
          reason: 'Authenticate to open ${AppStrings.appName}',
        );

    if (!mounted) return;

    switch (result) {
      case AuthResult.success:
        _unlock();
      case AuthResult.notAvailable:
        // Device doesn't support auth — let them in anyway
        _unlock();
      case AuthResult.notEnrolled:
        setState(() {
          _isAuthenticating = false;
          _canBypass = true;
          _errorMessage =
              'No biometrics or device PIN are set up. '
              'Go to your device Settings to add a PIN or fingerprint, '
              'or continue without lock protection.';
        });
      case AuthResult.error:
        setState(() {
          _isAuthenticating = false;
          _canBypass = true;
          _errorMessage =
              'This device could not start authentication. Tap to try '
              'again, or continue without the lock and turn it off in '
              'Settings.';
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
      case AuthResult.lockedOut:
        setState(() {
          _errorMessage = AppStrings.authLockedOut;
          _isAuthenticating = false;
        });
      case AuthResult.permanentlyLockedOut:
        setState(() {
          _errorMessage = AppStrings.authPermanentlyLockedOut;
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
                const KashuMark(size: 88, glow: true),

                const SizedBox(height: 32),

                const KashuWordmark(fontSize: 28),

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
                  if (_canBypass) ...[
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _unlock,
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
