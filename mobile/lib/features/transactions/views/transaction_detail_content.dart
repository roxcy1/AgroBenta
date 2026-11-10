import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/listing.dart';
import '../../../models/transaction.dart';
import '../../../widgets/detail_row.dart';
import '../../../widgets/section_card.dart';
import '../../livestock_types/state/livestock_types_scope.dart';
import '../state/transaction_timeline.dart';
import '../widgets/transaction_progress_timeline.dart';
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
///    location, so no badge and no location row are rendered. It is the seller
///    for a buyer and the buyer for a seller, as the server's `role` says;
///  * the resource links to **no inquiry**, and there is no mobile inquiry read
///    endpoint (GAP-19), so the inquiry section is an honest statement rather
///    than a fabricated record.
class TransactionDetailContent extends StatelessWidget {
  const TransactionDetailContent({
    required this.transaction,
    required this.isCancelling,
    required this.isUpdating,
    required this.activeAction,
    required this.cancelErrorMessage,
    required this.actionErrorMessage,
    required this.canCancel,
    required this.onCancel,
    required this.onDismissCancelError,
    required this.onDismissActionError,
    required this.onAction,
    required this.onMessageCounterparty,
    required this.onViewStatus,
    required this.onViewReceipt,
    super.key,
  });

  final Transaction transaction;
  final bool isCancelling;
  final bool isUpdating;
  final TransactionFulfillmentAction? activeAction;
  final String? cancelErrorMessage;
  final String? actionErrorMessage;
  final bool canCancel;
  final VoidCallback onCancel;
  final VoidCallback onDismissCancelError;
  final VoidCallback onDismissActionError;
  final ValueChanged<TransactionFulfillmentAction> onAction;

  /// Opens the existing conversation with the counterparty. The counterparty
  /// id comes from the payload, so this routes to a real, server-identifiable
  /// user and never to an invented one.
  final VoidCallback onMessageCounterparty;

  /// Opens the dedicated Transaction Status screen for this same record.
  final VoidCallback onViewStatus;

  /// Opens the completed sale's receipt. The caller only offers this to the
  /// buyer of a completed transaction.
  final VoidCallback onViewReceipt;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? photoUrl = transaction.listing.loadablePhotoUrl;
    final String? total = AppFormatters.formatMoney(transaction.totalAmount);
    final bool isSeller = transaction.role == TransactionRole.seller;
    final String counterpartyLabel = isSeller ? 'Buyer' : 'Seller';
    final String counterpartyAction = isSeller
        ? 'Message buyer'
        : 'Message seller';
    final String recordNoun = isSeller ? 'sale' : 'request';
    final bool isBusy = isCancelling || isUpdating;
    final bool hasUnknownStage = transaction.hasUnknownFulfillmentStatus;
    final TransactionFulfillmentAction? nextSellerAction = hasUnknownStage
        ? null
        : transaction.nextSellerAction;
    final bool canConfirmReceived =
        !hasUnknownStage && transaction.canConfirmReceived;
    final bool canViewReceipt =
        transaction.role == TransactionRole.buyer &&
        transaction.status == TransactionStatus.completed;

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
                _ActionErrorNotice(
                  message: cancelErrorMessage!,
                  onDismiss: onDismissCancelError,
                ),
              ],
              if (actionErrorMessage != null) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                _ActionErrorNotice(
                  message: actionErrorMessage!,
                  onDismiss: onDismissActionError,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              _AmountCard(total: total, transaction: transaction),
              const SizedBox(height: AppSpacing.md),
              _CollectionCard(transaction: transaction),
              const SizedBox(height: AppSpacing.md),
              SectionCard(
                title: counterpartyLabel,
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
                      onPressed: onMessageCounterparty,
                      icon: const Icon(Icons.chat_bubble_outline, size: 18),
                      label: Text(counterpartyAction),
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
                    value: LivestockTypesScope.labelOf(
                      context,
                      transaction.listing.livestockType,
                    ),
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
                    label: isSeller ? 'Recorded' : 'Requested',
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
              if (canViewReceipt) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onViewReceipt,
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: const Text('View receipt'),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              _InquiryCard(isSeller: isSeller),
              const SizedBox(height: AppSpacing.lg),
              if (nextSellerAction != null) ...<Widget>[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: isBusy ? null : () => onAction(nextSellerAction),
                    child: activeAction == nextSellerAction
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(nextSellerAction.label),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (canConfirmReceived) ...<Widget>[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: isBusy
                        ? null
                        : () => onAction(
                            TransactionFulfillmentAction.confirmReceived,
                          ),
                    icon:
                        activeAction ==
                            TransactionFulfillmentAction.confirmReceived
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Confirm Received'),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (canCancel)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: isBusy ? null : onCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                    ),
                    child: isCancelling
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text('Cancel $recordNoun'),
                  ),
                )
              else if (hasUnknownStage)
                Text(
                  'Fulfillment actions are unavailable until the app is updated.',
                  style: theme.textTheme.bodySmall,
                )
              else if (transaction.isPending &&
                  nextSellerAction == null &&
                  !canConfirmReceived)
                Text(
                  isSeller
                      ? 'Waiting for the buyer to confirm receipt.'
                      : 'Waiting for the seller to update the next fulfillment step.',
                  style: theme.textTheme.bodySmall,
                )
              else if (!transaction.isPending)
                Text(
                  'This $recordNoun is ${_statusWord(transaction.status)} and '
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

/// The recorded collection arrangement and preferred date.
///
/// These are the snapshotted preferences, not live logistics. No location,
/// rider, tracking or delivery fee is invented because the transaction record
/// does not carry them.
class _CollectionCard extends StatelessWidget {
  const _CollectionCard({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TransactionTerms terms = transaction.terms;
    final DateTime? pickupDate = terms.pickupDate;

    return SectionCard(
      title: 'Collection',
      children: <Widget>[
        DetailRow(label: 'Method', value: terms.collectionMethodLabel),
        if (pickupDate != null)
          DetailRow(
            label: 'Preferred date',
            value: AppFormatters.formatDate(pickupDate),
          ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          terms.isDelivery
              ? 'Delivery is arranged directly between the buyer and seller. '
                    'AgroBenta does not provide tracking or a rider.'
              : 'Pickup and transport are arranged directly between the buyer '
                    'and seller. AgroBenta does not provide transport.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// A safe state for a fulfillment stage this app version does not know.
class _UnknownFulfillmentNotice extends StatelessWidget {
  const _UnknownFulfillmentNotice();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warningSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.info_outline, size: 18, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Status unavailable', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'The server returned a fulfillment status this version of '
                  'the app does not recognize. Update the app to see the '
                  'current stage. No action is shown until then.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
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
    final bool isSeller = transaction.role == TransactionRole.seller;
    final bool hasUnknownStage = transaction.hasUnknownFulfillmentStatus;
    final TransactionFulfillmentStatus? stage =
        transaction.effectiveFulfillmentStatus;

    final String explanation = hasUnknownStage
        ? 'The server returned a fulfillment status this version of the app '
              'does not recognize. The current stage cannot be displayed '
              'safely until the app is updated.'
        : switch (transaction.status) {
            TransactionStatus.pending =>
              isSeller
                  ? _pendingExplanationForSeller(stage)
                  : _pendingExplanationForBuyer(stage),
            TransactionStatus.completed =>
              'This sale is complete. The record can no longer change.',
            TransactionStatus.cancelled =>
              isSeller
                  ? 'This sale was cancelled. The record can no longer change.'
                  : 'This request was cancelled. The record can no longer change.',
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
          if (transaction.isPending &&
              stage != null &&
              !hasUnknownStage) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Fulfillment: ${stage.label}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(explanation, style: theme.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.md),
          if (hasUnknownStage)
            const _UnknownFulfillmentNotice()
          else
            TransactionProgressTimeline(
              steps: TransactionTimeline.fulfillmentStepsFor(transaction),
            ),
          if (transaction.hasLegacyFulfillment) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'This older transaction has no recorded fulfillment stage. The '
              'tracker starts at Confirmed.',
              style: theme.textTheme.bodySmall,
            ),
          ],
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

  static String _pendingExplanationForBuyer(
    TransactionFulfillmentStatus? stage,
  ) {
    return switch (stage) {
      TransactionFulfillmentStatus.confirmed =>
        'The sale is confirmed. Waiting for the seller to start preparing.',
      TransactionFulfillmentStatus.preparing =>
        'The seller is preparing the livestock.',
      TransactionFulfillmentStatus.readyForPickup =>
        'The livestock is ready. Arrange the handover with the seller.',
      TransactionFulfillmentStatus.pickedUp =>
        'The seller reported the handover. Confirm receipt when you have the livestock.',
      TransactionFulfillmentStatus.onTheWay =>
        'The seller has dispatched the livestock.',
      TransactionFulfillmentStatus.delivered =>
        'The seller reported delivery. Confirm receipt when you have the livestock.',
      TransactionFulfillmentStatus.completed =>
        'Waiting for the final record update.',
      null => 'The fulfillment stage is not recorded for this transaction.',
    };
  }

  static String _pendingExplanationForSeller(
    TransactionFulfillmentStatus? stage,
  ) {
    return switch (stage) {
      TransactionFulfillmentStatus.confirmed =>
        'The sale is confirmed. Start preparing when you are ready.',
      TransactionFulfillmentStatus.preparing =>
        'Prepare the livestock for pickup or delivery.',
      TransactionFulfillmentStatus.readyForPickup =>
        'Marked ready for pickup. Confirm handover when the buyer collects it.',
      TransactionFulfillmentStatus.pickedUp =>
        'Handover reported. Waiting for the buyer to confirm receipt.',
      TransactionFulfillmentStatus.onTheWay =>
        'The livestock is on the way to the buyer.',
      TransactionFulfillmentStatus.delivered =>
        'Delivery reported. Waiting for the buyer to confirm receipt.',
      TransactionFulfillmentStatus.completed =>
        'Waiting for the final record update.',
      null => 'The fulfillment stage is not recorded for this transaction.',
    };
  }
}

/// An honest statement about the inquiry link.
///
/// The design asks for a summary of the linked inquiry. The mobile API has no
/// inquiry read endpoint (GAP-19) and `MobileTransactionResource` links to no
/// inquiry at all, so there is nothing real to render. Rather than fabricate a
/// message or a timestamp, the section states the capability is not available.
class _InquiryCard extends StatelessWidget {
  const _InquiryCard({required this.isSeller});

  final bool isSeller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SectionCard(
      title: isSeller ? 'Buyer inquiry' : 'Your inquiry',
      children: <Widget>[
        Text(
          isSeller
              ? 'The inquiry linked to this sale is not viewable in the app '
                    'yet. Reading a saved inquiry is not supported by the '
                    'current API.'
              : 'The inquiry you sent is not viewable in the app yet. Reading '
                    'a saved inquiry is not supported by the current API.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// A cancel/action failure above the record, which stays on screen.
class _ActionErrorNotice extends StatelessWidget {
  const _ActionErrorNotice({required this.message, required this.onDismiss});

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
