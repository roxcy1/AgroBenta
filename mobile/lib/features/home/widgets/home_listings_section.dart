import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/listing.dart';
import '../../marketplace/state/marketplace_controller.dart';
import '../../marketplace/state/marketplace_state.dart';
import '../../marketplace/widgets/listing_card.dart';

/// Card width for the compact row. The shared [ListingCard] is designed for a
/// full-width list; at this width its title may wrap to two lines, so the row
/// height below must budget for that.
const double _cardWidth = 230;

/// Row height: the card's 16:9 photo band (~125px at [_cardWidth]), plus its
/// content — species, a two-line title, price and up to two meta rows — plus
/// the card's own margin. Measured against the real card rather than guessed,
/// because a fixed-height row that overflows is a yellow-and-black stripe on
/// every buyer's Home screen.
const double _rowHeight = 320;

/// The Home screen's listings row, driven by the shared marketplace state.
///
/// "Recent Listings" and not "Featured Livestock": the backend offers no
/// featured flag, no featured endpoint and no approved selection rule
/// (`AgroBenta_Home_DESIGN (1).md` §3.5 forbids the label without one), while
/// `GET /listings` *does* order `created_at DESC, id DESC` — so "recent" is a
/// claim the server actually backs. The row shows the first few listings of
/// that server-ordered first page, straight from
/// [MarketplaceController.state]; it makes no request of its own and invents
/// nothing.
///
/// Sharing the controller with the marketplace tab is deliberate: one page-1
/// fetch serves both screens, the controller's in-flight guard makes the
/// second screen's `loadInitial` a no-op, and a search typed on Home is
/// already in the state when the buyer opens the marketplace.
class HomeListingsSection extends StatelessWidget {
  const HomeListingsSection({
    required this.controller,
    required this.onOpenListing,
    this.onSeeAll,
    super.key,
  });

  /// The session-scoped marketplace controller, read-only from here.
  final MarketplaceController controller;

  /// Opens the existing listing-detail screen for a tapped card.
  final ValueChanged<Listing> onOpenListing;

  /// Switches the shell to the Marketplace tab. Null omits the action.
  final VoidCallback? onSeeAll;

  /// How many cards the row shows. The marketplace tab carries the full list
  /// and its pagination; Home is a preview, not a second paginated list.
  static const int _previewCount = 6;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? child) {
        final MarketplaceState state = controller.state;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenGutter,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Recent Listings',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (onSeeAll != null)
                    TextButton(
                      onPressed: onSeeAll,
                      child: const Text('See All'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            _body(state),
          ],
        );
      },
    );
  }

  Widget _body(MarketplaceState state) {
    switch (state.status) {
      case MarketplaceStatus.initial:
      case MarketplaceStatus.loading:
        return const _LoadingRow();

      case MarketplaceStatus.failed:
        return _ErrorRow(
          message: state.errorMessage ?? 'Something went wrong.',
          onRetry: controller.retry,
        );

      case MarketplaceStatus.ready:
      case MarketplaceStatus.loadingMore:
      case MarketplaceStatus.refreshing:
        if (state.listings.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.screenGutter,
              vertical: AppSpacing.sm,
            ),
            child: Text('No active listings yet.'),
          );
        }
        return _ListingRow(
          listings: state.listings.take(_previewCount).toList(growable: false),
          onOpenListing: onOpenListing,
        );
    }
  }
}

/// The horizontal row of compact listing cards.
///
/// The shared [ListingCard] at a fixed width, so Home shows exactly the card
/// the marketplace shows — same photo/placeholder behaviour, same money
/// formatting, same fields — instead of a second card design to keep in step.
class _ListingRow extends StatelessWidget {
  const _ListingRow({required this.listings, required this.onOpenListing});

  final List<Listing> listings;
  final ValueChanged<Listing> onOpenListing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _rowHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenGutter,
        ),
        itemCount: listings.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: AppSpacing.sm),
        itemBuilder: (BuildContext context, int index) {
          final Listing listing = listings[index];
          return SizedBox(
            width: _cardWidth,
            child: ListingCard(
              listing: listing,
              onTap: () => onOpenListing(listing),
            ),
          );
        },
      ),
    );
  }
}

/// Skeleton cards for the first load, matching the row's shape.
class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _rowHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenGutter,
        ),
        itemCount: 2,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: AppSpacing.sm),
        // The same fixed width the real cards get: a horizontal list gives its
        // children an unbounded width, and without it the skeleton's own
        // `double.infinity` placeholder has nothing to resolve against.
        itemBuilder: (BuildContext context, int index) => const SizedBox(
          width: _cardWidth,
          child: _SkeletonCard(),
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  border: Border.all(color: AppColors.border),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _Bar(width: 90),
            const SizedBox(height: AppSpacing.xs),
            _Bar(width: 140),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 12,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

/// A compact failure for the section: the rest of Home is still usable, so the
/// listings row reports the problem and offers a retry rather than replacing
/// the screen with an error state.
class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenGutter,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline, size: 20, color: AppColors.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
