import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/seller_activity.dart';

/// One row in a seller activity feed (Seller Home and All Activities).
///
/// The icon is chosen from the action, the label and description come from the
/// server, and the timestamp is relative. A row is tappable only when the host
/// resolved a safe destination; otherwise it renders without a chevron.
class SellerActivityTile extends StatelessWidget {
  const SellerActivityTile({
    required this.activity,
    required this.onTap,
    this.boxed = false,
    super.key,
  });

  final SellerActivity activity;
  final VoidCallback? onTap;

  /// Whether the row sits inside a bordered list, which needs side padding
  /// and puts the time at the right edge instead of under the text.
  final bool boxed;

  static IconData iconFor(String action) {
    if (action.startsWith('inquiry')) {
      return Icons.mark_email_unread_outlined;
    }
    if (action.startsWith('offer')) {
      return Icons.local_offer_outlined;
    }
    if (action == 'listing_marked_sold') {
      return Icons.task_alt_outlined;
    }
    if (action.startsWith('listing')) {
      return Icons.storefront_outlined;
    }
    if (action.startsWith('transaction')) {
      return Icons.receipt_long_outlined;
    }
    return Icons.circle_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String timestamp = AppFormatters.formatRelative(activity.createdAt);
    final String? description = activity.description;

    final Widget content = Padding(
      padding: EdgeInsets.symmetric(
        vertical: boxed ? AppSpacing.sm : AppSpacing.xs,
        horizontal: boxed ? AppSpacing.sm : 0,
      ),
      child: Row(
        crossAxisAlignment: boxed
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: <Widget>[
          // The event's icon on a pale tile, as in the approved design.
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              iconFor(activity.action),
              size: 19,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  activity.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (description != null &&
                    description.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (!boxed && timestamp.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    timestamp,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (boxed && timestamp.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.xs),
              child: Text(
                timestamp,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            )
          else if (onTap != null)
            const Padding(
              padding: EdgeInsets.only(left: AppSpacing.xs),
              child: Icon(Icons.chevron_right, size: 20),
            ),
        ],
      ),
    );

    if (onTap == null) {
      return content;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: boxed ? null : BorderRadius.circular(AppRadius.sm),
      child: content,
    );
  }
}
