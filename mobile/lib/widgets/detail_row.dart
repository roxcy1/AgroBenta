import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';

/// A labelled detail row — the compact record row used across the app's detail
/// screens.
///
/// The label is a secondary value above, never beside, the value: on a phone a
/// label beside its value forces the value into a narrow right-hand column and
/// reads like a table. Stacking keeps the value the primary text.
class DetailRow extends StatelessWidget {
  const DetailRow({required this.label, required this.value, super.key})
    : body = null;

  /// Paragraph form, for a description or note that has no label.
  const DetailRow.body(String this.body, {super.key})
    : label = null,
      value = null;

  final String? label;
  final String? value;

  /// Paragraph form, for a description or notes field.
  final String? body;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? paragraph = body;

    if (paragraph != null) {
      return Text(paragraph, style: theme.textTheme.bodyMedium);
    }

    // Label on the left, value on the right, on a hairline: a compact
    // key-value table, as in the approved design.
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              value!,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
