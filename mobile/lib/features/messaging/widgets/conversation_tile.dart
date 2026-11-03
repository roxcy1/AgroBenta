import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
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

    return Material(
      // Pale green while the thread has unread messages — the theme's own
      // primarySurface, so it matches every other soft-green surface in the
      // app (Messages design §3.4, §7).
      color: unread ? AppColors.primarySurface : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenGutter,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Avatar(user: conversation.counterpart, hasUnread: unread),
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
                              fontWeight: unread
                                  ? FontWeight.w600
                                  : FontWeight.w500,
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
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            _listingLabel(conversation),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_statusLabel(conversation) != null) ...<Widget>[
                          const SizedBox(width: AppSpacing.xs),
                          _StatusChip(
                            label: _statusLabel(conversation)!,
                            emphasised:
                                conversation.latestOffer?.isPending ?? false,
                          ),
                        ],
                      ],
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
                              fontWeight: unread
                                  ? FontWeight.w500
                                  : FontWeight.normal,
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
      ),
    );
  }

  /// The listing context line: the most relevant listing, its asking price and,
  /// when the thread spans more than one listing, how many others there are.
  static String _listingLabel(Conversation conversation) {
    final String title = conversation.listingTitle ?? 'Direct message';
    final String? price = conversation.listingPrice == null
        ? null
        : AppFormatters.formatMoney(conversation.listingPrice!);
    final String base = price == null ? title : '$title · $price';
    if (conversation.listingCount > 1) {
      return '$base · +${conversation.listingCount - 1} more listings';
    }
    return base;
  }

  /// The single status the preview shows, most specific first: a pending
  /// offer, then a decided offer, then the pair-level inquiry/transaction
  /// facts. `null` when the thread carries no status worth a chip.
  static String? _statusLabel(Conversation conversation) {
    final ConversationOffer? offer = conversation.latestOffer;
    if (offer != null) {
      return offer.isPending
          ? 'Offer pending'
          : 'Offer ${offer.status.label.toLowerCase()}';
    }
    if (conversation.hasInquiry) {
      return 'Inquiry';
    }
    if (conversation.hasTransaction) {
      return 'Transaction';
    }
    return null;
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
        style: Theme.of(context).textTheme.headlineSmall,
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
              : CircleAvatar(radius: 24, backgroundImage: NetworkImage(url)),
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

/// The thread-status chip: pale green for a live offer, neutral otherwise.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.emphasised});

  final String label;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color background = emphasised
        ? AppColors.primarySurface
        : AppColors.surface;
    final Color foreground = emphasised
        ? AppColors.primary
        : AppColors.textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxxs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: emphasised ? AppColors.primary : AppColors.border,
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: emphasised ? FontWeight.w600 : FontWeight.w500,
        ),
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxxs,
      ),
      constraints: const BoxConstraints(minWidth: 20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
