import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/listing.dart';
import '../../../widgets/paged_list_state_views.dart';
import '../../marketplace/widgets/listing_card.dart';
import '../../marketplace/widgets/marketplace_state_views.dart';
import '../state/seller_profile_state.dart';

/// The text block under a card photo. Kept in step with the marketplace grid so
/// the two-card layout reads the same everywhere.
const double _cardTextHeight = 124;

/// The Listings tab: the seller's marketplace-visible inventory only.
///
/// The cards and the grid are the marketplace's, not a second design. The
/// server has already excluded draft, pending, sold, inactive, reconciled and
/// fully reserved listings, and it has already applied the search, category and
/// ordering, so this widget renders exactly the page it receives.
class SellerListingsTab extends StatelessWidget {
  const SellerListingsTab({
    required this.state,
    required this.onRefresh,
    required this.onRetry,
    required this.onLoadMore,
    required this.onClearFilters,
    required this.onOpenListing,
    super.key,
  });

  final SellerProfileState state;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;
  final VoidCallback onLoadMore;
  final VoidCallback onClearFilters;
  final ValueChanged<Listing> onOpenListing;

  @override
  Widget build(BuildContext context) {
    switch (state.listingsStatus) {
      case SellerListingsStatus.initial:
      case SellerListingsStatus.loading:
        return const _LoadingListings();
      case SellerListingsStatus.failed:
        return MarketplaceErrorState(
          title: 'Could not load listings',
          message:
              state.listingsErrorMessage ??
              'Something went wrong. Please try again.',
          onRetry: onRetry,
        );
      case SellerListingsStatus.unavailable:
        return const _UnavailableListings();
      case SellerListingsStatus.ready:
      case SellerListingsStatus.loadingMore:
      case SellerListingsStatus.refreshing:
        if (state.listings.isEmpty) {
          return _EmptyListings(
            isFiltered: state.hasActiveListingFilters,
            onRefresh: onRefresh,
            onClearFilters: onClearFilters,
          );
        }
        return _ListingsGrid(
          state: state,
          onRefresh: onRefresh,
          onLoadMore: onLoadMore,
          onOpenListing: onOpenListing,
        );
    }
  }
}

class _ListingsGrid extends StatelessWidget {
  const _ListingsGrid({
    required this.state,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onOpenListing,
  });

  final SellerProfileState state;
  final Future<void> Function() onRefresh;
  final VoidCallback onLoadMore;
  final ValueChanged<Listing> onOpenListing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double spacing = AppSpacing.sm;
        final double availableWidth =
            constraints.maxWidth - (AppSpacing.screenGutter * 2);
        final double itemWidth = (availableWidth - spacing) / 2;
        final double itemExtent = (itemWidth * 3 / 4) + _cardTextHeight;

        return RefreshIndicator(
          onRefresh: onRefresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              if (state.listingsRefreshErrorMessage != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenGutter,
                      AppSpacing.md,
                      AppSpacing.screenGutter,
                      0,
                    ),
                    child: PagedListRefreshNotice(
                      message: state.listingsRefreshErrorMessage!,
                      onRetry: onRefresh,
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenGutter,
                  AppSpacing.md,
                  AppSpacing.screenGutter,
                  0,
                ),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    // Fixed at two: a single matching listing keeps the card
                    // size and grid rhythm of a full row instead of stretching
                    // across the screen.
                    crossAxisCount: 2,
                    mainAxisSpacing: spacing,
                    crossAxisSpacing: spacing,
                    mainAxisExtent: itemExtent,
                  ),
                  delegate: SliverChildBuilderDelegate((
                    BuildContext context,
                    int index,
                  ) {
                    final Listing listing = state.listings[index];
                    return ListingCard(
                      listing: listing,
                      onTap: () => onOpenListing(listing),
                    );
                  }, childCount: state.listings.length),
                ),
              ),
              SliverToBoxAdapter(
                child: PagedListLoadMoreFooter(
                  isLoading:
                      state.listingsStatus == SellerListingsStatus.loadingMore,
                  hasMore: state.hasMoreListings,
                  errorMessage: state.listingsLoadMoreErrorMessage,
                  onLoadMore: onLoadMore,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LoadingListings extends StatelessWidget {
  const _LoadingListings();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Loading listings',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

/// Shown only after a 404 from the listings endpoint: the seller stopped being
/// public while the tab was open. A retry cannot change that, so none is
/// offered; the app bar goes back.
class _UnavailableListings extends StatelessWidget {
  const _UnavailableListings();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.visibility_off_outlined,
              size: 40,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Listings unavailable',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'This seller no longer has public listings.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyListings extends StatelessWidget {
  const _EmptyListings({
    required this.isFiltered,
    required this.onRefresh,
    required this.onClearFilters,
  });

  final bool isFiltered;
  final Future<void> Function() onRefresh;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.screenGutter),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      isFiltered
                          ? Icons.search_off_outlined
                          : Icons.inventory_2_outlined,
                      size: 40,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      isFiltered ? 'No listings match' : 'No active listings',
                      style: theme.textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      isFiltered
                          ? 'Try a different search, category or sort order.'
                          : 'This seller has no listings available right now.',
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    if (isFiltered) ...<Widget>[
                      const SizedBox(height: AppSpacing.lg),
                      OutlinedButton(
                        onPressed: onClearFilters,
                        child: const Text('Clear filters'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
