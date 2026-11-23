import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';

/// A compact, accessible indicator for server-approved sellers.
///
/// Callers decide visibility only from the API's `is_verified` value; this
/// widget does not infer approval from account or conversation roles.
class VerifiedSellerBadge extends StatelessWidget {
  const VerifiedSellerBadge({this.compact = false, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double iconSize = compact ? 12 : 14;
    final String visibleLabel = compact ? 'Verified' : 'Verified Seller';

    return Semantics(
      container: true,
      label: 'Verified Seller',
      child: ExcludeSemantics(
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 0 : AppSpacing.xs,
            vertical: AppSpacing.xxxs,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.success),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.verified, size: iconSize, color: AppColors.success),
              const SizedBox(width: AppSpacing.xxxs),
              Text(
                visibleLabel,
                style:
                    (compact
                            ? theme.textTheme.labelSmall
                            : theme.textTheme.labelMedium)
                        ?.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.w600,
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
