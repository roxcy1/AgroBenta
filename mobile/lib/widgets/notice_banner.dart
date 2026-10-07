import 'package:flutter/material.dart';

import '../core/theme/app_spacing.dart';

/// A coloured, left-railed notice explaining a status or a failed action.
///
/// The shape used for conflict notices, action errors and administrative notes
/// across the app. The **word** still carries the meaning — the accent is a
/// supporting signal, not the message itself, per `mobile/DESIGN.md`.
///
/// When [title] is supplied the notice renders as a labelled block (used for an
/// administrator's note); otherwise it renders as an icon plus a single line of
/// text (used for conflicts and action errors).
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    required this.accent,
    this.icon,
    required this.message,
    this.title,
    this.backgroundColor,
    super.key,
  });

  /// The rail colour. Semantic status colours only.
  final Color accent;

  /// The supporting icon, rendered in the single-line form.
  final IconData? icon;

  final String message;

  /// An optional heading above the message.
  final String? title;

  /// Background tint. Defaults to the card surface.
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: backgroundColor ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: title == null
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 20, color: accent),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Expanded(child: Text(message, style: theme.textTheme.bodySmall)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title!, style: theme.textTheme.labelMedium),
                const SizedBox(height: AppSpacing.xxs),
                Text(message, style: theme.textTheme.bodyMedium),
              ],
            ),
    );
  }
}