import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/offer.dart';
import '../state/offer_state.dart';
import 'offer_status_badge.dart';

/// The purchase-offer panel above a chat's composer.
///
/// Shows every **pending** offer exchanged with this counterpart, because each
/// one is still actionable and a buyer must be able to answer an older offer
/// even after a newer one arrives. When nothing is pending it falls back to the
/// newest offer so the thread keeps the outcome visible. The conversation is
/// the buyer–seller pair, so offers from any of their listings belong here.
///
/// Actions are role-scoped from the server's `buyer_id` / `seller_id`:
/// the buyer accepts or declines, the seller withdraws. The server enforces
/// the same rule regardless, so these buttons are a convenience over a real
/// check, never a replacement for it.
class ChatOfferPanel extends StatelessWidget {
  const ChatOfferPanel({
    required this.state,
    required this.currentUserId,
    required this.onAccept,
    required this.onDecline,
    required this.onWithdraw,
    required this.onRetry,
    super.key,
  });

  final ChatOffersState state;
  final int currentUserId;
  final ValueChanged<Offer> onAccept;
  final ValueChanged<Offer> onDecline;
  final ValueChanged<Offer> onWithdraw;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // Nothing to show yet. Loading and an empty result both stay silent so a
    // thread without offers is not given a permanent empty panel.
    if (state.offers.isEmpty) {
      if (state.status == ChatOffersStatus.failed) {
        return _OfferErrorRow(message: state.errorMessage, onRetry: onRetry);
      }
      return const SizedBox.shrink();
    }

    // Pending offers are all actionable; a terminal record is shown only when
    // there is nothing left to answer, so the panel never hides an action.
    final List<Offer> pending = state.offers
        .where((Offer offer) => offer.status.isPending)
        .toList(growable: false);
    final List<Offer> shown = pending.isEmpty
        ? <Offer>[state.offers.first]
        : pending;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.sm,
        AppSpacing.screenGutter,
        AppSpacing.xs,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.local_offer_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  shown.length == 1 ? 'Purchase offer' : 'Purchase offers',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (
                    int index = 0;
                    index < shown.length;
                    index++
                  ) ...<Widget>[
                    if (index > 0) const Divider(height: AppSpacing.lg),
                    _offerBlock(theme, shown[index]),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _offerBlock(ThemeData theme, Offer offer) {
    final bool isBuyer = offer.isBuyer(currentUserId);
    final bool isSeller = offer.isSeller(currentUserId);
    final bool isBusy = state.busyOfferId == offer.id;
    final String amount =
        AppFormatters.formatMoney(offer.proposedAmount) ?? offer.proposedAmount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                amount,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: AppColors.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            OfferStatusBadge(status: offer.status),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          _caption(offer, isBuyer: isBuyer),
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        if (offer.status.isPending && (isBuyer || isSeller)) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          if (isBusy)
            const Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                height: AppSizes.controlHeight,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ),
            )
          else if (isBuyer)
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onDecline(offer),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: FilledButton(
                    onPressed: () => onAccept(offer),
                    child: const Text('Accept offer'),
                  ),
                ),
              ],
            )
          else
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => onWithdraw(offer),
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Withdraw offer'),
              ),
            ),
        ],
      ],
    );
  }

  /// One true sentence per side and state. No accepted offer claims a
  /// transaction link here: `OfferResource` carries no transaction id, so the
  /// only honest link is the one shown in the accept response dialog.
  String _caption(Offer offer, {required bool isBuyer}) {
    return switch (offer.status) {
      OfferStatus.pending =>
        isBuyer
            ? 'The seller proposed this price for your inquiry.'
            : 'Waiting for the buyer to accept or decline.',
      OfferStatus.accepted =>
        isBuyer ? 'You accepted this offer.' : 'The buyer accepted this offer.',
      OfferStatus.declined =>
        isBuyer ? 'You declined this offer.' : 'The buyer declined this offer.',
      OfferStatus.withdrawn =>
        isBuyer
            ? 'The seller withdrew this offer.'
            : 'You withdrew this offer.',
      OfferStatus.expired => 'This offer expired.',
    };
  }
}

class _OfferErrorRow extends StatelessWidget {
  const _OfferErrorRow({required this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenGutter,
        vertical: AppSpacing.xs,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              message ?? 'Could not load offers.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
