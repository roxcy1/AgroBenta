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
/// with no photos by drawing a labelled placeholder. A draft may have none, but
/// it cannot be submitted for review until it does (DEC-03), so the draft's
/// submit action is blocked with an inline reason rather than failing at the
/// server.
///
/// Tappable as a whole, with the row as the only tap target. The action buttons
/// are a separate footer rather than icons inside the row, because a delete that
/// removes a record needs a wider, unambiguous target than a trailing chevron.
class SellerListingCard extends StatelessWidget {
  const SellerListingCard({
    required this.listing,
    required this.onTap,
    required this.onSubmit,
    required this.onMarkSold,
    required this.onEdit,
    required this.onDelete,
    this.busy = false,
    super.key,
  });

  final Listing listing;
  final VoidCallback onTap;

  /// Submits the draft for review.
  final VoidCallback onSubmit;

  /// Marks the listing as sold.
  final VoidCallback onMarkSold;

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
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm - 2),
                    child: SizedBox(
                      width: 84,
                      height: 84,
                      child: ListingPhoto(listing: listing),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        // Name and status on one line, then what and
                        // where, then the price, as in the approved design.
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                listing.title,
                                style: theme.textTheme.titleSmall,
                                maxLines: 2,
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
                        const SizedBox(height: AppSpacing.xxxs),
                        _MetaRow(
                          icon: Icons.place_outlined,
                          text: <String>[
                            // Sentence case, as on the buyer's listing card.
                            if (listing.livestockType.trim().isNotEmpty)
                              '${listing.livestockType.trim()[0].toUpperCase()}'
                                  '${listing.livestockType.trim().substring(1)}',
                            if (listing.location.trim().isNotEmpty)
                              listing.location.trim(),
                          ].join(' · '),
                        ),
                        const SizedBox(height: AppSpacing.xxxs),
                        _MetaRow(
                          icon: Icons.scale_outlined,
                          text: _physicalSummary(),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          AppFormatters.formatMoneyCompact(
                                listing.askingPrice,
                              ) ??
                              listing.askingPrice,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
            onView: onTap,
            onSubmit: onSubmit,
            onMarkSold: onMarkSold,
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
      if (listing.weightLabel != null)
        '${listing.weightIsEstimated ? 'Est. ' : ''}${listing.weightLabel!}',
      if (listing.ageLabel != null)
        '${listing.ageIsEstimated ? 'Est. ' : ''}${listing.ageLabel!}',
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
    required this.onView,
    required this.onSubmit,
    required this.onMarkSold,
    required this.onEdit,
    required this.onDelete,
  });

  final Listing listing;
  final bool busy;
  final VoidCallback onView;
  final VoidCallback onSubmit;
  final VoidCallback onMarkSold;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool canSubmit = SellerListingController.canSubmit(listing);
    final bool canMarkSold = SellerListingController.canMarkSold(listing);
    final bool hasPhotos = SellerListingController.hasSubmissionPhotos(listing);

    final List<Widget> actions = <Widget>[];
    switch (listing.status) {
      case ListingStatus.draft:
        actions.add(
          _compactAction(
            icon: Icons.edit_outlined,
            label: 'Edit',
            onPressed: onEdit,
          ),
        );
        actions.add(
          _compactAction(
            icon: Icons.send_outlined,
            label: 'Submit',
            onPressed: hasPhotos ? onSubmit : null,
          ),
        );
        break;
      case ListingStatus.active:
        actions.add(
          _compactAction(
            icon: Icons.edit_outlined,
            label: 'Edit',
            onPressed: onEdit,
          ),
        );
        actions.add(
          _compactAction(
            icon: Icons.done_outline,
            label: 'Mark sold',
            onPressed: canMarkSold ? onMarkSold : null,
            color: AppColors.sold,
          ),
        );
        break;
      case ListingStatus.pending:
      case ListingStatus.sold:
        actions.add(
          _compactAction(
            icon: Icons.visibility_outlined,
            label: 'View',
            onPressed: onView,
          ),
        );
        break;
      case ListingStatus.inactive:
        actions.add(
          _compactAction(
            icon: Icons.delete_outline,
            label: 'Delete',
            onPressed: onDelete,
            color: AppColors.error,
          ),
        );
        break;
    }

    final bool showExplanation =
        !canSubmit && !canMarkSold && listing.status != ListingStatus.inactive;

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xxs,
        AppSpacing.sm,
        AppSpacing.xxs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (listing.status == ListingStatus.draft && !hasPhotos)
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.xxs),
              child: ListingPhotoRequirementNotice(),
            ),
          if (showExplanation)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: Text(
                listingStatusExplanation(listing.status),
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Align(
                alignment: Alignment.centerRight,
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (actions.isNotEmpty)
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.xxs,
              runSpacing: AppSpacing.xxs,
              children: actions,
            ),
        ],
      ),
    );
  }

  /// A compact, right-aligned action: icon plus a short label, with a 44dp
  /// minimum height so the touch target stays usable in the dense card footer.
  Widget _compactAction({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    Color? color,
  }) {
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        visualDensity: VisualDensity.compact,
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
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
