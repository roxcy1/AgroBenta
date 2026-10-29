import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/listing.dart';
import '../../../models/user.dart';
import '../../auth/state/auth_scope.dart';
import '../../auth/state/auth_state.dart';
import '../../auth/widgets/auth_error_banner.dart';
import '../../marketplace/state/listing_filters.dart';
import '../../marketplace/state/marketplace_controller.dart';
import '../../marketplace/state/marketplace_scope.dart';
import '../../marketplace/views/listing_detail_screen.dart';
import '../../marketplace/views/marketplace_filter_screen.dart';
import '../../marketplace/widgets/marketplace_filter_button.dart';
import '../../notifications/state/notifications_scope.dart';
import '../../seller_listings/widgets/seller_listings_entry_card.dart';
import '../widgets/home_categories.dart';
import '../widgets/home_header.dart';
import '../widgets/home_hero_banner.dart';
import '../widgets/home_listings_section.dart';

/// The authenticated landing screen, per the approved Home design.
///
/// The page hierarchy is header, search, hero banner, categories and recent
/// listings — vertically scrollable, with the buyer shell's bottom navigation
/// remaining the only tab bar. The header stays pinned above the scroll so the
/// notifications bell and the profile action are always reachable.
///
/// ## Everything marketplace-shaped is shared, not duplicated
///
/// The search field, the filter button and the listings row are all driven by
/// the session-scoped [MarketplaceController] the marketplace tab already uses
/// (`MarketplaceScope`, installed in `main.dart`). This screen makes no
/// request the marketplace would not make: the controller's in-flight guard
/// turns the second `loadInitial` into a no-op, a search typed here is the
/// same state the marketplace list reads, and categories apply the existing
/// exact-match `livestock_type` filter rather than an invented query. One
/// page-1 fetch serves both screens.
///
/// The account card, the seller-verification entry and the sign-out action of
/// the previous Home are gone: the approved design ends at Recent Listings.
/// Sign out lives on the profile screen; the seller-only My Listings entry
/// remains at the bottom because it is the app's only path into that screen.
class BuyerHomeScreen extends StatefulWidget {
  const BuyerHomeScreen({
    this.onBrowseMarketplace,
    this.onOpenProfile,
    super.key,
  });

  /// Switches the shell to the Marketplace tab.
  ///
  /// Injected rather than reached for, so this screen does not have to know
  /// how the shell is built or hold a reference to it. Null renders the
  /// marketplace-bound affordances without their buttons, which is what a test
  /// or a standalone use of this screen wants.
  final VoidCallback? onBrowseMarketplace;

  /// Switches the shell to the Profile tab. Null omits the header's avatar
  /// action rather than rendering a dead control.
  final VoidCallback? onOpenProfile;

  @override
  State<BuyerHomeScreen> createState() => _BuyerHomeScreenState();
}

class _BuyerHomeScreenState extends State<BuyerHomeScreen> {
  late final MarketplaceController _marketplace;
  late final TextEditingController _searchField;

  @override
  void initState() {
    super.initState();
    // Refresh the badge count on every visit to Home. `readOf` because
    // `initState` cannot register an inherited-widget dependency; the
    // `ListenableBuilder` in the header registers it once we are in `build`.
    NotificationsScope.readOf(context).refreshUnreadCount();

    _marketplace = MarketplaceScope.readOf(context).controller;
    _searchField = TextEditingController(text: _marketplace.state.searchText);
    _marketplace.addListener(_onMarketplaceChanged);

    // Fires once, when the shell first builds this tab. Safe to call
    // unconditionally: the marketplace screen calls the same method, and the
    // controller ignores a request while one identical query is in flight, so
    // the two tabs share a single page-1 fetch.
    _marketplace.loadInitial();
  }

  @override
  void dispose() {
    _marketplace.removeListener(_onMarketplaceChanged);
    _searchField.dispose();
    super.dispose();
  }

  /// Keeps the field in step when the search text changes somewhere other than
  /// the field itself — the marketplace tab's own field, or this screen's
  /// filter sheet changing the query.
  ///
  /// A listener rather than a call from `build`: writing to a
  /// `TextEditingController` during build notifies the field, which marks it
  /// dirty during that same build and throws. The equality check makes it a
  /// no-op whenever the text already matches, so it never fights the user's
  /// own cursor.
  void _onMarketplaceChanged() {
    if (!mounted) {
      return;
    }
    final String value = _marketplace.state.searchText;
    if (value == _searchField.text) {
      return;
    }
    _searchField.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  /// Commits the search immediately (skipping the debounce) and follows the
  /// buyer to the marketplace, where the results and the rest of the query
  /// controls live.
  void _submitSearch() {
    _marketplace.submitSearch();
    widget.onBrowseMarketplace?.call();
  }

  void _clearSearch() {
    // Clearing the field programmatically does not fire its `onChanged`, so
    // the shared state must be told directly — otherwise it still holds the
    // old text and the listener above writes it straight back into the field.
    _searchField.clear();
    _marketplace.updateSearch('');
    _marketplace.submitSearch();
  }

  /// Opens the Filter Livestock screen, applies what comes back through the
  /// shared controller, and continues to the marketplace.
  Future<void> _openFilters() async {
    final ListingFilters? applied = await showMarketplaceFilterScreen(
      context: context,
      filters: _marketplace.state.filters,
    );

    if (!mounted || applied == null) {
      return;
    }
    // Fire-and-forget: the request starts immediately, the marketplace tab
    // shows the loading state, and the buyer does not wait for the response
    // before the tab switches.
    unawaited(_marketplace.applyFilters(applied));
    widget.onBrowseMarketplace?.call();
  }

  /// Applies a category as the marketplace's existing exact-match
  /// `livestock_type` filter, then follows the buyer to the marketplace tab.
  void _selectCategory(HomeCategory category) {
    unawaited(
      _marketplace.applyFilters(
        _marketplace.state.filters.copyWith(
          livestockType: category.livestockType,
        ),
      ),
    );
    widget.onBrowseMarketplace?.call();
  }

  void _openListing(Listing listing) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            ListingDetailScreen(listingId: listing.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AuthState state = AuthScope.of(context).state;
    final User? user = state.user;

    // A signed-in state always carries a user. Rendering nothing rather than
    // crashing keeps a contract surprise from becoming a red screen.
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Home')),
        body: SafeArea(
          child: Center(
            child: Text('No account loaded.', style: theme.textTheme.bodySmall),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            HomeHeader(user: user, onOpenProfile: widget.onOpenProfile),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _Greeting(user: user),
                        const SizedBox(height: AppSpacing.sm),
                        ListenableBuilder(
                          listenable: _marketplace,
                          builder: (BuildContext context, Widget? child) {
                            return _SearchBar(
                              controller: _marketplace,
                              searchField: _searchField,
                              onSubmit: _submitSearch,
                              onClear: _clearSearch,
                              onOpenFilters: _openFilters,
                            );
                          },
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        HomeHeroBanner(onExplore: widget.onBrowseMarketplace),
                        const SizedBox(height: AppSpacing.lg),
                        HomeCategories(
                          onSelect: _selectCategory,
                          onSeeAll: widget.onBrowseMarketplace,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        HomeListingsSection(
                          controller: _marketplace,
                          onOpenListing: _openListing,
                          onSeeAll: widget.onBrowseMarketplace,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        if (state.errorMessage != null) ...<Widget>[
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.screenGutter,
                            ),
                            child: AuthErrorBanner(
                              message: state.errorMessage!,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                        // Seller-only, and only when `/auth/me` says the
                        // account is a seller. A buyer never sees it, which is
                        // also why My Listings is not a tab in the buyer shell's
                        // bottom navigation: the tab would exist for them and
                        // lead to a screen whose every request is a 403. Seller
                        // Mode has its own shell and a real My Listings tab.
                        if (user.isSeller)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.screenGutter,
                            ),
                            child: SellerListingsEntryCard(user: user),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The greeting above the search bar. Uses the real account name — never a
/// placeholder — and stays small so the marketplace hierarchy leads.
class _Greeting extends StatelessWidget {
  const _Greeting({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.xs,
        AppSpacing.screenGutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Buyer Mode',
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text('Hello, ${user.name}!', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Happy trading!',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The rounded search field and the filter button, wired to the shared
/// marketplace controller.
///
/// The placeholder is the design's approved copy. One honest caveat, reported
/// with this change: the backend's free-text search matches `livestock_type`,
/// `breed` and `location` — not the seller's name — so a seller name typed
/// here will not find that seller's listings.
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.searchField,
    required this.onSubmit,
    required this.onClear,
    required this.onOpenFilters,
  });

  final MarketplaceController controller;
  final TextEditingController searchField;
  final VoidCallback onSubmit;
  final VoidCallback onClear;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) {
    final bool hasText = controller.state.searchText.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenGutter),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: searchField,
              textInputAction: TextInputAction.search,
              onChanged: controller.updateSearch,
              // Committing from the keyboard skips the remaining debounce and
              // follows the buyer to the results.
              onSubmitted: (String _) => onSubmit(),
              decoration: InputDecoration(
                hintText: 'Search livestock, seller, or location...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: hasText
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Clear search',
                        onPressed: onClear,
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          MarketplaceFilterButton(
            state: controller.state,
            onPressed: onOpenFilters,
          ),
        ],
      ),
    );
  }
}
