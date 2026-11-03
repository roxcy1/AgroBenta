import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

/// A confirmation shown above a form: the counterpart of `AuthErrorBanner`.
class AuthNoticeBanner extends StatelessWidget {
  const AuthNoticeBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.success),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(
              Icons.check_circle_outline,
              size: 20,
              color: AppColors.success,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
