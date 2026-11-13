import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/message.dart';
import 'inquiry_message_card.dart';

/// One message bubble in a chat thread.
///
/// Aligned left for the counterpart's messages, right for the caller's own.
/// A placeholder (negative id, sent optimistically) renders in a reduced
/// opacity with a small clock marker until the server confirms it.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    required this.isMine,
    required this.isPlaceholder,
    super.key,
  });

  final Message message;
  final bool isMine;
  final bool isPlaceholder;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // The opening inquiry message renders as a structured card, not as the
    // generated prose body the server also stores.
    final MessageInquiry? inquiry = message.inquiry;
    if (inquiry != null) {
      return InquiryMessageCard(inquiry: inquiry, isMine: isMine);
    }

    // Sent: brand green. Received: white with a hairline border, as in the
    // approved design.
    final Color bubbleColor = isMine ? AppColors.primary : AppColors.surface;

    final Color textColor = isMine ? Colors.white : AppColors.text;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.75,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxs),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: bubbleColor.withValues(alpha: isPlaceholder ? 0.7 : 1),
              border: isMine ? null : Border.all(color: AppColors.border),
              // The corner nearest the sender is tighter, like a speech tail.
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: Radius.circular(isMine ? 12 : 4),
                bottomRight: Radius.circular(isMine ? 4 : 12),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  message.body,
                  style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      _timeLabel(message.createdAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: textColor.withValues(alpha: 0.7),
                      ),
                    ),
                    if (isPlaceholder) ...<Widget>[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.schedule,
                        size: 10,
                        color: textColor.withValues(alpha: 0.7),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _timeLabel(DateTime? at) {
    if (at == null) {
      return '';
    }
    final DateTime local = at.toLocal();
    final String h = local.hour.toString().padLeft(2, '0');
    final String m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
