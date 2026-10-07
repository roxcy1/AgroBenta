import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/listing.dart';
import '../../marketplace/widgets/listing_photo.dart';
import '../state/seller_listing_controller.dart';
import '../view/seller_listing_views.dart';

/// One listing in the seller's own list.
///
/// Deliberately **not** [ListingCard]. That card is written for a buyer: it
/// leaves out `health_status` and the seller's name because a buyer has no use
/// for them, and it has no notion of a listing that is not live. This one is the
/// seller's own record, so it inverts those decisions — the status is the first
/// thing shown, the health status belongs in it, and the actions the server will
/// accept are on the card rather than one tap away.
///
/// The thumbnail reuses [ListingPhoto] unchanged. It already handles a listing
/// with no photos by drawing a labelled placeholder, which is what every draft
/// and `pending` listing currently is: photo upload is not in the contract yet
/// (GAP-06), so the placeholder is the normal case, not an edge case.
///
/// Tappable as a whole, with the row as the only tap target. The action buttons
/// are a separate footer rather than icons inside the row, because a delete that
/// removes a record needs a wider, unambiguous target than a trailing chevron.
class SellerListingCard extends StatelessWidget {
  const SellerListingCard({
    required this.listing,
    required this.onTap,
    required this.onSubmit,
    required this.onEdit,
    required this.onDelete,
    this.busy = false,
    super.key,
  });

  final Listing listing;
  final VoidCallback onTap;

  /// Submits the draft for review.
  final VoidCallback onSubmit;

  /// Edits the listing.
  final VoidCallback onEdit;

  /// Deletes the listing.
  final VoidCallback onDelete;

  /// Whether an action on **this** listing is in flight.
  ///
  /// Driven by [SellerListingState.actionListingId] rather than by a global
  /// "busy" flag, so a submission on one row does not dim the other nine. The
  /// whole card's controls are disabled either way — a second action while one is
  /// in flight is a `409` waiting to happen — but the spinner is local.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 88,
                    height: 88,
                    child: ListingPhoto(listing: listing),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                listing.livestockType,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            ListingStatusChip(
                              status: listing.status,
                              dense: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          listing.title,
                          style: theme.textTheme.titleSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          AppFormatters.formatMoneyCompact(
                                listing.askingPrice,
                              ) ??
                              listing.askingPrice,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: AppColors.primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        _MetaRow(
                          icon: Icons.place_outlined,
                          text: listing.location,
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        _MetaRow(
                          icon: Icons.scale_outlined,
                          text: _physicalSummary(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          _ActionBar(
            listing: listing,
            busy: busy,
            onSubmit: onSubmit,
            onEdit: onEdit,
            onDelete: onDelete,
          ),
        ],
      ),
    );
  }

  /// Age, weight and quantity, skipping anything not recorded.
  String _physicalSummary() {
    final List<String> parts = <String>[
      if (listing.quantity > 0)
        '${listing.quantity} ${listing.quantity == 1 ? 'head' : 'heads'}',
      if (listing.weightLabel != null) listing.weightLabel!,
      if (listing.ageLabel != null) listing.ageLabel!,
    ];
    return parts.isEmpty ? 'No size details yet' : parts.join(' · ');
  }
}

/// The actions the server will accept for this listing, and nothing else.
///
/// Built from [SellerListingController]'s mirrors of the server rules rather than
/// from an ad-hoc `if` per status, so the button set and the rules stay in one
/// place. A `pending` listing yields an empty bar and an explanatory line: it is
/// in an administrator's queue and there is genuinely nothing the seller can do,
/// which is information worth stating rather than a row of disabled buttons.
///
/// Destructive actions are the outlined style, never the filled one. A filled
/// button on a card is a call to action; deletion is not one, and it is the only
/// action here that cannot be undone.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.listing,
    required this.busy,
    required this.onSubmit,
    required this.onEdit,
    required this.onDelete,
  });

  final Listing listing;
  final bool busy;
  final VoidCallback onSubmit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool canEdit = SellerListingController.canEdit(listing);
    final bool canSubmit = SellerListingController.canSubmit(listing);
    final bool canDelete = SellerListingController.canDelete(listing);

    if (!canEdit && !canSubmit && !canDelete) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.md,
        ),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Text(
          listingStatusExplanation(listing.status),
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          if (canEdit)
            Expanded(
              child: TextButton.icon(
                onPressed: busy ? null : onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
            ),
          if (canSubmit)
            Expanded(
              child: busy
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
                        child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : TextButton.icon(
                      onPressed: onSubmit,
                      icon: const Icon(Icons.send_outlined, size: 18),
                      label: const Text('Submit'),
                    ),
            ),
          if (canDelete)
            Expanded(
              child: TextButton.icon(
                onPressed: busy ? null : onDelete,
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Delete'),
              ),
            ),
        ],
      ),
    );
  }
}

/// A small icon-and-label pair.
///
/// `ExcludeSemantics` on the icon so a screen reader hears "Mabalacat, Pampanga"
/// rather than "place Mabalacat, Pampanga".
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      children: <Widget>[
        ExcludeSemantics(
          child: Icon(icon, size: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
