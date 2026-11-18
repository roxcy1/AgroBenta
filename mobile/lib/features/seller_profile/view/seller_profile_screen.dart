import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/listing.dart';
import '../../../models/livestock_type.dart';
import '../../../models/seller_profile.dart';
import '../../../repositories/marketplace_repository.dart';
import '../../../widgets/paged_list_state_views.dart';
import '../../livestock_types/state/livestock_types_controller.dart';
import '../../livestock_types/state/livestock_types_scope.dart';
import '../../livestock_types/state/livestock_types_state.dart';
import '../../marketplace/state/marketplace_scope.dart';
import '../../marketplace/views/listing_detail_screen.dart';
import '../../marketplace/widgets/marketplace_state_views.dart';
import '../../auth/state/auth_scope.dart';
import '../../user_reports/view/report_user_screen.dart';
import '../state/seller_profile_controller.dart';
import '../state/seller_profile_state.dart';
import '../widgets/seller_listings_tab.dart';
import '../widgets/seller_profile_details_tab.dart';
import '../widgets/seller_profile_filters.dart';
import '../widgets/seller_profile_header.dart';
import '../widgets/seller_profile_summary.dart';
import '../widgets/seller_profile_tab_bar.dart';

/// A seller's public profile, as a buyer sees it.
///
/// Reached from the seller card on Listing Details and given only the
/// `users.id` from that listing's narrowed seller projection. Nothing is seeded
/// from the listing: the profile and its listings are re-fetched, following the
/// same reason `ListingDetailScreen` re-fetches a listing — the copy on the
/// previous screen may no longer be current.
///
/// Reads the shared marketplace repository from `MarketplaceScope` in
/// `initState`, so no new scope or composition-root wiring is needed. The
/// controller is per-screen and disposed with the route.
///
/// The screen has exactly two tabs: Profile and Listings. There is no message,
/// offer, transaction or rating action here; those flows are untouched and stay
/// where they already live.
class SellerProfileScreen extends StatefulWidget {
  const SellerProfileScreen({required this.sellerId, super.key});

  /// `users.id` from `listing.seller.id`.
  final int sellerId;

  @override
  State<SellerProfileScreen> createState() => _SellerProfileScreenState();
}

class _SellerProfileScreenState extends State<SellerProfileScreen> {
  late final SellerProfileController _controller;
  late final LivestockTypesController _livestockTypes;
  late final TextEditingController _searchField;

  @override
  void initState() {
    super.initState();
    final MarketplaceRepository repository = MarketplaceScope.readOf(
      context,
    ).repository;
    _controller = SellerProfileController(repository, widget.sellerId);
    _livestockTypes = LivestockTypesScope.readOf(context);
    _searchField = TextEditingController();
    _controller.load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _livestockTypes.ensureLoaded();
    });
  }

  @override
  void dispose() {
    _searchField.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Clears the search field and asks the controller to reset every filter.
  void _clearFilters() {
    _searchField.clear();
    _controller.clearListingFilters();
  }

  /// Clears only the search, keeping the category and ordering.
  void _clearSearch() {
    _searchField.clear();
    _controller.clearSearch();
  }

  /// Opens one of the seller's listings. Back returns here with the selected
  /// tab and its scroll position intact.
  void _openListing(Listing listing) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            ListingDetailScreen(listingId: listing.id),
      ),
    );
  }

  /// Opens the shared report form for this public seller.
  void _reportSeller() {
    final int? viewerId = AuthScope.maybeOf(context)?.state.user?.id;
    if (viewerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in again to report this seller.')),
      );
      return;
    }
    if (viewerId == widget.sellerId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot report your own account.')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ReportUserScreen(
          reportedUserId: widget.sellerId,
          reportedUserName: _controller.state.profile?.name ?? 'Seller',
          reportedUserRole: 'Seller',
          currentUserId: viewerId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int? viewerId = AuthScope.maybeOf(context)?.state.user?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Seller Profile'),
        actions: <Widget>[
          PopupMenuButton<String>(
            tooltip: 'Seller options',
            onSelected: (String value) {
              if (value == 'report') _reportSeller();
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'report',
                enabled: viewerId != null && viewerId != widget.sellerId,
                child: const Text('Report Seller'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: _controller,
          builder: (BuildContext context, Widget? child) {
            final SellerProfileState state = _controller.state;

            if (state.status == SellerProfileStatus.initial ||
                state.status == SellerProfileStatus.loading) {
              return const _ProfileLoadingState();
            }

            if (state.status == SellerProfileStatus.unavailable) {
              return const _ProfileUnavailableState();
            }

            if (state.status == SellerProfileStatus.failed) {
              return MarketplaceErrorState(
                title: 'Could not load seller profile',
                message: state.errorMessage ?? 'Something went wrong.',
                onRetry: _controller.load,
              );
            }

            final SellerProfile? profile = state.profile;
            if (profile == null) {
              // `ready`/`refreshing` always carries a profile; this is only a
              // non-crashing answer for an impossible frame.
              return const SizedBox.shrink();
            }

            return Column(
              children: <Widget>[
                SellerProfileHeader(profile: profile),
                SellerProfileSummary(profile: profile),
                if (state.refreshErrorMessage != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenGutter,
                      AppSpacing.md,
                      AppSpacing.screenGutter,
                      0,
                    ),
                    child: PagedListRefreshNotice(
                      message: state.refreshErrorMessage!,
                      onRetry: _controller.refresh,
                    ),
                  ),
                SellerProfileTabBar(
                  selected: state.selectedTab,
                  onSelected: _controller.selectTab,
                ),
                if (state.selectedTab == SellerProfileTab.listings)
                  ListenableBuilder(
                    listenable: _livestockTypes,
                    builder: (BuildContext context, Widget? child) {
                      final LivestockTypesState catalog = _livestockTypes.state;
                      return SellerProfileFilters(
                        searchController: _searchField,
                        state: state,
                        types: catalog.isReady
                            ? catalog.types
                            : const <LivestockType>[],
                        onSearchChanged: _controller.updateSearch,
                        onSearchSubmitted: _controller.submitSearch,
                        onClearSearch: _clearSearch,
                        onSelectCategory: _controller.selectCategory,
                        onSelectSort: _controller.selectSort,
                        onClearFilters: _clearFilters,
                      );
                    },
                  ),
                Expanded(
                  child: IndexedStack(
                    index: state.selectedTab.index,
                    children: <Widget>[
                      SellerProfileDetailsTab(
                        profile: profile,
                        onRefresh: _controller.refresh,
                      ),
                      SellerListingsTab(
                        state: state,
                        onRefresh: _controller.refresh,
                        onRetry: _controller.retryListings,
                        onLoadMore: _controller.loadMoreListings,
                        onClearFilters: _clearFilters,
                        onOpenListing: _openListing,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProfileLoadingState extends StatelessWidget {
  const _ProfileLoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Loading seller profile',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

/// The seller is gone, deleted, or has nothing public to show. The server
/// deliberately does not say which, so the copy does not either.
class _ProfileUnavailableState extends StatelessWidget {
  const _ProfileUnavailableState();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.person_off_outlined,
              size: 40,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Seller profile unavailable',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'This seller may no longer have an active account or public '
              'listings.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Back to listing'),
            ),
          ],
        ),
      ),
    );
  }
}
