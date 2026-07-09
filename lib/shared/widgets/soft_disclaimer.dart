import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_theme.dart';

/// Shared bottom-of-screen disclaimer, calm by design.
///
/// Renders a single neutral sentence in a soft container — no warning
/// colors, just a quiet note at the end of a screen.
class SoftDisclaimer extends StatelessWidget {
  final String text;

  const SoftDisclaimer(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.tile),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: AppColors.textTertiaryOn(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTheme.body(
                size: 11.5,
                weight: FontWeight.w500,
                color: AppColors.textTertiaryOn(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
