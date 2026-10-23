import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/listing.dart';
import '../../../models/transaction.dart';
import '../state/transaction_timeline.dart';
import '../widgets/transaction_progress_timeline.dart';
import '../widgets/transaction_status_badge.dart';

/// What the Transaction Status screen shows once the record is visible.
///
/// Everything is sourced from a single `GET /transactions/{id}` payload
/// (`MobileTransactionResource`). The screen never widens it:
///
///  * the money field is the server-derived `total_amount`. The resource does
///    **not** carry the listing's `asking_price`, so no reference-versus-agreed
///    pair is shown — inventing the reference side would misrepresent the
///    record;
///  * there is **no status history** and no per-step timestamps in the backend,
///    so the progress tracker is a summary of the real state machine (see
///    [TransactionTimeline]) and an explicit note says a dated history is not
///    recorded. No step date is fabricated;
///  * there is no location, no seller-verification flag and no delivery field
///    on the record, so none is rendered.
class TransactionStatusContent extends StatelessWidget {
  const TransactionStatusContent({
    required this.transaction,
    required this.onMessageSeller,
    super.key,
  });

  final Transaction transaction;

  /// Opens the existing conversation with the counterparty, from the payload's
  /// real counterparty id. Never an invented endpoint or contact.
  final VoidCallback onMessageSeller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<TimelineStep> steps = TransactionTimeline.stepsFor(
      transaction.status,
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: <Widget>[
        _ListingSummaryCard(transaction: transaction),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _MetadataCard(transaction: transaction),
              const SizedBox(height: AppSpacing.lg),
              Text('Transaction Progress', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              TransactionProgressTimeline(steps: steps),
              const SizedBox(height: AppSpacing.md),
              const _HistoryUnavailableNote(),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onMessageSeller,
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('Message Seller'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The listing summary: image (when a real, loadable URL exists), title, the
/// server-derived total and the current status badge.
class _ListingSummaryCard extends StatelessWidget {
  const _ListingSummaryCard({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? photoUrl = transaction.listing.loadablePhotoUrl;
    final String? total = AppFormatters.formatMoney(transaction.totalAmount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (photoUrl != null && Listing.isDirectlyLoadablePhotoUrl(photoUrl))
          SizedBox(
            height: 200,
            width: double.infinity,
            child: Image.network(
              photoUrl.trim(),
              fit: BoxFit.cover,
              errorBuilder: (BuildContext context, Object e, StackTrace? _) =>
                  const SizedBox.shrink(),
              excludeFromSemantics: true,
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.md,
            AppSpacing.screenGutter,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                transaction.listing.title,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              TransactionStatusBadge(status: transaction.status),
              const SizedBox(height: AppSpacing.md),
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
                'The listing\'s reference asking price is not part of the '
                'transaction and is not shown.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Compact metadata: the request id and the persisted requested date/time.
class _MetadataCard extends StatelessWidget {
  const _MetadataCard({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _MetadataRow(
            icon: Icons.confirmation_number_outlined,
            label: 'Request ID',
            value: transaction.displayId,
          ),
          const SizedBox(height: AppSpacing.sm),
          _MetadataRow(
            icon: Icons.event_outlined,
            label: 'Requested',
            value: AppFormatters.formatDateTime(transaction.createdAt),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'The time this request was created. It is the only recorded '
            'timestamp; individual steps are not timed.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: theme.textTheme.labelSmall),
              const SizedBox(height: AppSpacing.xxs),
              Text(value, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

/// The honest statement about the missing history.
///
/// The design's reference shows five dated steps. The backend records one
/// current status and no transition history, so a dated timeline does not
/// exist. Rather than fabricate step dates, the screen says so plainly [§5].
class _HistoryUnavailableNote extends StatelessWidget {
  const _HistoryUnavailableNote();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.info_outline, size: 18, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'This tracker summarises the request\'s current status. The '
              'system records only the current status, not a dated history of '
              'each step, so no per-step dates are shown.',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.text),
            ),
          ),
        ],
      ),
    );
  }
}
