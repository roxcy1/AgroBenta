import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/conversation.dart';
import '../../../models/message.dart';

/// One row in the conversations list.
///
/// Tappable as a whole. Shows the counterpart's avatar, name, last message
/// preview, a time marker, and an unread badge when there is one.
class ConversationTile extends StatelessWidget {
  const ConversationTile({
    required this.conversation,
    required this.onTap,
    super.key,
  });

  final Conversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool unread = conversation.hasUnread;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenGutter,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _Avatar(
              user: conversation.counterpart,
              hasUnread: unread,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          conversation.counterpart.name,
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
                        _shortTime(conversation.lastMessageAt),
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
                    conversation.listingTitle ?? 'Direct message',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          conversation.lastMessage,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: unread
                                ? theme.colorScheme.onSurface
                                : AppColors.textSecondary,
                            fontWeight:
                                unread ? FontWeight.w500 : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (unread) ...<Widget>[
                        const SizedBox(width: AppSpacing.xs),
                        _UnreadBadge(count: conversation.unreadCount),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A compact time label for the row — "now", "5m", "14:32", "3d", "12/10".
  ///
  /// Inlined rather than delegated to `AppFormatters` because the shape a
  /// conversation list wants is a different shape from a date field, and a
  /// dedicated helper here keeps the rule (what a chat list shows when) in
  /// one place next to the widget it serves.
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
      final String h = local.hour.toString().padLeft(2, '0');
      final String m = local.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays}d';
    }
    return '${local.day}/${local.month}';
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user, required this.hasUnread});

  final ChatUser user;
  final bool hasUnread;

  @override
  Widget build(BuildContext context) {
    final String? url = user.avatarUrl;
    final Widget fallback = CircleAvatar(
      radius: 24,
      child: Text(
        user.initial,
        style: const TextStyle(fontSize: 18),
      ),
    );

    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          url == null || url.isEmpty
              ? fallback
              : CircleAvatar(
                  radius: 24,
                  backgroundImage: NetworkImage(url),
                ),
          if (hasUnread)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final String label = count > 99 ? '99+' : count.toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      constraints: const BoxConstraints(minWidth: 20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}