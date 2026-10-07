import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/listing.dart';
import 'listing_photo.dart';

/// One listing in the marketplace list.
///
/// A card a buyer can judge from a thumbnail: what it is, what it costs, where
/// it is, and how much of it there is. Deliberately **not** every column —
/// `health_status`, `vaccination`, `additional_notes` and the seller's name
/// belong on the detail screen, and a card that lists everything is a card
/// nobody can scan.
///
/// Layout is the photo on top and the facts below, per `mobile/DESIGN.md` §14:
/// the image is the first thing a buyer scanning livestock wants to see, so it
/// leads the card at a fixed aspect ratio instead of squeezing beside the text
/// as a small square.
///
/// Tappable as a whole. The [onTap] target is the full card, comfortably past
/// the 48dp minimum, and the card is the only interactive element inside it —
/// nested tap targets inside a tappable row are a mis-tap problem, not a
/// feature.
class ListingCard extends StatelessWidget {
  const ListingCard({required this.listing, required this.onTap, super.key});

  final Listing listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // The photo takes the whole card width at a fixed aspect ratio, so
            // every card has the same-shaped image band and the list stays
            // scannable when sellers write very different amounts of text.
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ListingPhoto(listing: listing),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // Species first and in a label style: it is the broadest
                  // thing a buyer scanning for "cattle" is looking for, and
                  // the title below narrows it.
                  Text(
                    listing.livestockType,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    listing.title,
                    style: theme.textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  // Price, left-aligned and outside a pill, per the type
                  // rules. Never the only thing carrying the value: the peso
                  // symbol is part of the formatted string, so it reads
                  // without colour.
                  Text(
                    AppFormatters.formatMoneyCompact(listing.askingPrice) ??
                        listing.askingPrice,
                    style: theme.textTheme.titleMedium?.copyWith(
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
                  if (listing.weightLabel != null ||
                      listing.quantity > 0) ...<Widget>[
                    const SizedBox(height: AppSpacing.xxs),
                    _MetaRow(
                      icon: Icons.scale_outlined,
                      text: _physicalSummary(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Age, weight and quantity in one line, skipping anything not recorded.
  ///
  /// Only the parts a seller actually filled in are shown. A card that renders
  /// "Age: —" for a listing with no age recorded is noise.
  String _physicalSummary() {
    final List<String> parts = <String>[
      if (listing.quantity > 0)
        '${listing.quantity} ${listing.quantity == 1 ? 'head' : 'heads'}',
      if (listing.weightLabel != null) listing.weightLabel!,
      if (listing.ageLabel != null) listing.ageLabel!,
    ];
    return parts.isEmpty ? 'Details on request' : parts.join(' · ');
  }
}

/// A small icon-and-label pair.
///
/// The icon is `excludeFromSemantics` so a screen reader hears
/// "Mabalacat, Pampanga" rather than "place Mabalacat, Pampanga": the glyph
/// carries no information the text does not.
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
