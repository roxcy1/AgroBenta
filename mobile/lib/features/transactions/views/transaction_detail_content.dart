import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/listing.dart';
import '../../../models/transaction.dart';
import '../../../widgets/detail_row.dart';
import '../../../widgets/section_card.dart';
import '../widgets/transaction_status_badge.dart';

/// What the detail screen shows once the transaction is confirmed visible.
class TransactionDetailContent extends StatelessWidget {
  const TransactionDetailContent({
    required this.transaction,
    required this.isCancelling,
    required this.cancelErrorMessage,
    required this.canCancel,
    required this.onCancel,
    required this.onDismissCancelError,
    super.key,
  });

  final Transaction transaction;
  final bool isCancelling;
  final String? cancelErrorMessage;
  final bool canCancel;
  final VoidCallback onCancel;
  final VoidCallback onDismissCancelError;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? photoUrl = transaction.listing.loadablePhotoUrl;

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: <Widget>[
        if (photoUrl != null && Listing.isDirectlyLoadablePhotoUrl(photoUrl))
          SizedBox(
            height: 220,
            child: Image.network(
              photoUrl.trim(),
              fit: BoxFit.cover,
              errorBuilder: (BuildContext context, Object e, StackTrace? _) =>
                  const SizedBox.shrink(),
              excludeFromSemantics: true,
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                transaction.displayId,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(transaction.listing.title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.xs),
              TransactionStatusBadge(status: transaction.status),
              const SizedBox(height: AppSpacing.md),
              // The exact amount, to the cent. The card rounds for space;
              // here there is room, and this is the server's figure.
              Text(
                AppFormatters.formatMoney(transaction.totalAmount) ??
                    transaction.totalAmount,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                '${transaction.quantity} '
                '${transaction.quantity == 1 ? 'head' : 'heads'}',
                style: theme.textTheme.bodySmall,
              ),
              if (cancelErrorMessage != null) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                _CancelErrorNotice(
                  message: cancelErrorMessage!,
                  onDismiss: onDismissCancelError,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              SectionCard(
                title: 'Counterparty',
                children: <Widget>[
                  DetailRow(label: 'Name', value: transaction.counterparty.name),
                  DetailRow(label: 'Email', value: transaction.counterparty.email),
                  DetailRow(
                    label: 'Your role',
                    value: transaction.role == TransactionRole.buyer
                        ? 'Buyer'
                        : 'Seller',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SectionCard(
                title: 'Dates',
                children: <Widget>[
                  DetailRow(
                    label: 'Created',
                    value: AppFormatters.formatDateTime(transaction.createdAt),
                  ),
                  DetailRow(
                    label: 'Updated',
                    value: AppFormatters.formatDateTime(transaction.updatedAt),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              // Cancel is offered to buyer and seller alike, pending-only.
              // Terminal records get an immutable notice, never a button.
              // There is no "Mark complete" here at all (OQ-15).
              if (canCancel)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: isCancelling ? null : onCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                    ),
                    child: isCancelling
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Cancel transaction'),
                  ),
                )
              else
                Text(
                  'This transaction is ${transaction.status.value} and cannot be changed.',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A cancel failure above the record, which stays on screen.
class _CancelErrorNotice extends StatelessWidget {
  const _CancelErrorNotice({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline, size: 18, color: AppColors.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.text),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
        ],
      ),
    );
  }
}
