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
///
/// Everything here is sourced from a single `GET /transactions/{id}` payload.
/// `MobileTransactionResource` is narrower than the marketplace listing
/// resource, and the screen never widens it:
///
///  * the embedded listing carries **identity, species, breed and photos** —
///    no age, weight, gender, health or location, so no attribute rows exist
///    for values the record does not hold;
///  * the money field is the server-derived `total_amount` — the resource does
///    **not** carry the listing's `asking_price`, so a "reference price vs
///    agreed price" pair cannot be shown without inventing one side, and the
///    screen says so instead of fabricating it;
///  * the counterparty is `{ id, name, email }` — no verification flag and no
///    location, so no badge and no location row are rendered;
///  * the resource links to **no inquiry**, and there is no mobile inquiry read
///    endpoint (GAP-19), so the "Your inquiry" section is an honest statement
///    rather than a fabricated record.
class TransactionDetailContent extends StatelessWidget {
  const TransactionDetailContent({
    required this.transaction,
    required this.isCancelling,
    required this.cancelErrorMessage,
    required this.canCancel,
    required this.onCancel,
    required this.onDismissCancelError,
    required this.onMessageSeller,
    required this.onViewStatus,
    super.key,
  });

  final Transaction transaction;
  final bool isCancelling;
  final String? cancelErrorMessage;
  final bool canCancel;
  final VoidCallback onCancel;
  final VoidCallback onDismissCancelError;

  /// Opens the existing conversation with the counterparty. The counterparty
  /// id comes from the payload, so this routes to a real, server-identifiable
  /// user and never to an invented one.
  final VoidCallback onMessageSeller;

  /// Opens the dedicated Transaction Status screen for this same record.
  final VoidCallback onViewStatus;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? photoUrl = transaction.listing.loadablePhotoUrl;
    final String? total = AppFormatters.formatMoney(transaction.totalAmount);

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
              _RequestHeader(transaction: transaction),
              if (cancelErrorMessage != null) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                _CancelErrorNotice(
                  message: cancelErrorMessage!,
                  onDismiss: onDismissCancelError,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              _AmountCard(total: total, transaction: transaction),
              const SizedBox(height: AppSpacing.md),
              SectionCard(
                title: 'Seller',
                children: <Widget>[
                  DetailRow(
                    label: 'Name',
                    value: transaction.counterparty.name,
                  ),
                  DetailRow(
                    label: 'Email',
                    value: transaction.counterparty.email,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onMessageSeller,
                      icon: const Icon(Icons.chat_bubble_outline, size: 18),
                      label: const Text('Message seller'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SectionCard(
                title: 'Livestock',
                children: <Widget>[
                  DetailRow(
                    label: 'Type',
                    value: transaction.listing.livestockType,
                  ),
                  if (transaction.listing.breed.trim().isNotEmpty)
                    DetailRow(label: 'Breed', value: transaction.listing.breed),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Age, weight, gender and health are not part of the '
                    'transaction record and are not shown.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SectionCard(
                title: 'Transaction',
                children: <Widget>[
                  DetailRow(label: 'Reference', value: transaction.displayId),
                  DetailRow(
                    label: 'Your role',
                    value: transaction.role == TransactionRole.buyer
                        ? 'Buyer'
                        : 'Seller',
                  ),
                  DetailRow(
                    label: 'Quantity',
                    value:
                        '${transaction.quantity} '
                        '${transaction.quantity == 1 ? 'head' : 'heads'}',
                  ),
                  DetailRow(
                    label: 'Requested',
                    value: AppFormatters.formatDateTime(transaction.createdAt),
                  ),
                  DetailRow(
                    label: 'Last updated',
                    value: AppFormatters.formatDateTime(transaction.updatedAt),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _StatusCard(transaction: transaction, onViewStatus: onViewStatus),
              const SizedBox(height: AppSpacing.md),
              const _InquiryCard(),
              const SizedBox(height: AppSpacing.lg),
              // Cancel is offered to buyer and seller alike, pending-only.
              // Terminal records get an immutable notice, never a button.
              // There is no "Mark complete" anywhere (OQ-15).
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
                        : const Text('Cancel request'),
                  ),
                )
              else
                Text(
                  'This request is ${_statusWord(transaction.status)} and '
                  'cannot be changed.',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _statusWord(TransactionStatus status) => switch (status) {
    TransactionStatus.pending => 'still open',
    TransactionStatus.completed => 'completed',
    TransactionStatus.cancelled => 'cancelled',
  };
}

/// The listing summary: reference id, title, status and the listing image's
/// key facts.
class _RequestHeader extends StatelessWidget {
  const _RequestHeader({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
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
      ],
    );
  }
}

/// The persisted money on the record.
///
/// `total_amount` is the server's `asking_price × quantity`. The resource does
/// not carry the listing's `asking_price`, so this screen cannot show a
/// reference-versus-agreed pair, and it does not pretend to: it labels the one
/// figure it has and states plainly what it is.
class _AmountCard extends StatelessWidget {
  const _AmountCard({required this.total, required this.transaction});

  final String? total;
  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SectionCard(
      title: 'Amount',
      children: <Widget>[
        Text('Transaction total', style: theme.textTheme.labelSmall),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          total ?? transaction.totalAmount,
          style: theme.textTheme.titleLarge?.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'The logged amount for this record. The listing\'s reference asking '
          'price is not part of the transaction and is not shown.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// The real lifecycle state, with a next step that is true of the workflow.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.transaction, required this.onViewStatus});

  final Transaction transaction;
  final VoidCallback onViewStatus;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    final String explanation = switch (transaction.status) {
      TransactionStatus.pending =>
        'A purchase request is not yet a completed sale. Either party can '
            'still cancel it.',
      TransactionStatus.completed =>
        'This sale is complete. The record can no longer change.',
      TransactionStatus.cancelled =>
        'This request was cancelled. The record can no longer change.',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('Status', style: theme.textTheme.titleSmall),
              const Spacer(),
              TransactionStatusBadge(status: transaction.status),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(explanation, style: theme.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onViewStatus,
              icon: const Icon(Icons.timeline_outlined, size: 18),
              label: const Text('View status'),
            ),
          ),
        ],
      ),
    );
  }
}

/// An honest statement about the inquiry link.
///
/// The design asks for a summary of the linked inquiry. The mobile API has no
/// inquiry read endpoint (GAP-19) and `MobileTransactionResource` links to no
/// inquiry at all, so there is nothing real to render. Rather than fabricate a
/// message or a timestamp, the section states the capability is not available.
class _InquiryCard extends StatelessWidget {
  const _InquiryCard();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SectionCard(
      title: 'Your inquiry',
      children: <Widget>[
        Text(
          'The inquiry you sent is not viewable in the app yet. Reading a '
          'saved inquiry is not supported by the current API.',
          style: theme.textTheme.bodySmall,
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
