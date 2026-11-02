import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/offer.dart';

/// The lifecycle badge for a purchase offer.
///
/// Colours are semantic, never decorative:
///
///  * `pending` → [AppColors.warning], the state that asks for a response;
///  * `accepted` → [AppColors.success], the only state that creates a record;
///  * `declined` / `withdrawn` / `expired` → neutral, terminal states that do
///    not need attention.
class OfferStatusBadge extends StatelessWidget {
  const OfferStatusBadge({required this.status, super.key});

  final OfferStatus status;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (Color foreground, Color background) = switch (status) {
      OfferStatus.pending => (AppColors.warning, AppColors.warningSurface),
      OfferStatus.accepted => (
        AppColors.success,
        AppColors.success.withValues(alpha: 0.12),
      ),
      OfferStatus.declined || OfferStatus.withdrawn || OfferStatus.expired => (
        AppColors.textSecondary,
        AppColors.textSecondary.withValues(alpha: 0.12),
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSizes.circular),
        border: Border.all(color: foreground.withValues(alpha: 0.4)),
      ),
      child: Text(
        status.label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
