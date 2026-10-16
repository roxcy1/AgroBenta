import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/app_notification.dart';

/// One notification in the inbox list.
///
/// Layout: a leading icon indicating the notification's category, then a
/// two-line body (title + summary), then a right-aligned timestamp and an
/// unread dot for unread notifications. Tappable as a whole.
class NotificationTile extends StatelessWidget {
  const NotificationTile({
    required this.notification,
    required this.onTap,
    super.key,
  });

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool unread = !notification.read;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenGutter,
          vertical: AppSpacing.sm,
        ),
        color: unread
            ? AppColors.primary.withValues(alpha: 0.04)
            : Colors.transparent,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _CategoryIcon(type: notification.type),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          notification.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight:
                                unread ? FontWeight.w600 : FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        _shortTime(notification.createdAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: unread
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    notification.body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: unread ? FontWeight.w500 : FontWeight.normal,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (unread) ...<Widget>[
              const SizedBox(width: AppSpacing.xs),
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// A compact time label — "now", "5m", "2h", "3d", "12/10".
  static String _shortTime(DateTime? at) {
    if (at == null) {
      return '';
    }
    final DateTime local = at.toLocal();
    final Duration diff = DateTime.now().difference(local);

    if (diff.inMinutes < 1) {
      return 'now';
    }
    if (diff.inHours < 1) {
      return '${diff.inMinutes}m';
    }
    if (diff.inDays < 1) {
      return '${diff.inHours}h';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays}d';
    }
    return '${local.day}/${local.month}';
  }
}

/// The leading icon for a notification, chosen by its category.
class _CategoryIcon extends StatelessWidget {
  const _CategoryIcon({required this.type});

  final NotificationType type;

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color color;

    switch (type) {
      case NotificationType.transactions:
        color = AppColors.primary;
        icon = Icons.receipt_long_outlined;
      case NotificationType.inquiries:
      case NotificationType.inquiry:
        color = Colors.blue;
        icon = Icons.chat_bubble_outline;
      case NotificationType.listings:
      case NotificationType.listing:
        color = Colors.orange;
        icon = Icons.inventory_2_outlined;
      case NotificationType.verification:
      case NotificationType.sellerVerification:
        color = Colors.green;
        icon = Icons.verified_outlined;
      case NotificationType.system:
        color = AppColors.textSecondary;
        icon = Icons.info_outline;
      case NotificationType.unknown:
        color = AppColors.textSecondary;
        icon = Icons.notifications_outlined;
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 20, color: color),
    );
  }
}