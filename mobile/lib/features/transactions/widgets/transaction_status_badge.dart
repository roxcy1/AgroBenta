import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/transaction.dart';

/// The lifecycle badge for a transaction.
///
/// Three distinct tokens, never confusable at a glance — the mapping
/// `mobile/DESIGN.md` §26 requires for transactions:
///
///  * `pending` (Ongoing) → neutral [AppColors.textSecondary]: still open,
///    deliberately not green, so it can never be mistaken for a completed row.
///    (§26 allows "green/neutral" for Ongoing; the neutral token is chosen so
///    green stays reserved for `completed` alone.)
///  * `completed` → [AppColors.success]: the only state that uses green.
///  * `cancelled` → [AppColors.error]: terminal dead end.
///
/// Status colours are never decorative.
class TransactionStatusBadge extends StatelessWidget {
  const TransactionStatusBadge({required this.status, super.key});

  final TransactionStatus status;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (Color foreground, Color background, String label) = switch (status) {
      TransactionStatus.pending => (
        AppColors.textSecondary,
        AppColors.textSecondary.withValues(alpha: 0.12),
        'Ongoing',
      ),
      TransactionStatus.completed => (
        AppColors.success,
        AppColors.success.withValues(alpha: 0.12),
        'Completed',
      ),
      TransactionStatus.cancelled => (
        AppColors.error,
        AppColors.error.withValues(alpha: 0.10),
        'Cancelled',
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(1000),
        border: Border.all(color: foreground.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
