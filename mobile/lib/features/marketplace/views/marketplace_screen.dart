import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_input_border.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/listing.dart';
import '../../../widgets/paged_list_state_views.dart';
import '../state/listing_filters.dart';
import '../state/marketplace_controller.dart';
import '../state/marketplace_scope.dart';
import '../state/marketplace_state.dart';
import '../widgets/listing_card.dart';
import '../widgets/marketplace_filter_button.dart';
import '../widgets/marketplace_state_views.dart';
import 'listing_detail_screen.dart';
import 'marketplace_filter_screen.dart';

/// The buyer marketplace.
///
/// A search field, a filter control and a list of [ListingCard]s, driven
/// entirely by [MarketplaceController.state]. The screen makes no request of its
/// own: it forwards intent to the controller and renders whatever state comes
/// back, so there is exactly one place where "what should be on screen" is
/// decided.
///
/// The controller is read once in `initState` and stored, because
/// [MarketplaceScope.of] registers a dependency — calling it from `build` would
/// mean the whole list rebuilt on every keystroke in the search field, and the
/// list is the expensive part of this screen.
/// Height of a listing card's text block under its photo: name, place and
/// price, with their padding. Slightly generous so a larger system font
/// still fits.
const double _cardTextHeight = 104;

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  late final MarketplaceController _controller;
  late final TextEditingController _searchField;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _controller = MarketplaceScope.readOf(context).controller;
    _searchField = TextEditingController(text: _controller.state.searchText);
    _scrollController = ScrollController()..addListener(_onScroll);
    _controller.addListener(_onControllerChanged);

    // Fires once, when the shell first builds this tab. Safe to call
    // unconditionally: the controller ignores a request while one is in flight
    // and drops stale responses, so a rebuild that re-enters here cannot
    // produce a second overlapping fetch.
    _controller.loadInitial();
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _searchField.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  /// Keeps the field in step when the search text changes somewhere other than
  /// the field itself — the empty state's "Clear search and filters" button, for
  /// instance.
  ///
  /// A listener rather than a call from `build`: writing to a
  /// `TextEditingController` during build notifies the field, which marks it
  /// dirty during that same build and throws. Doing it here also means it never
  /// fights the user's own cursor, since the equality check makes it a no-op
  /// whenever the text already matches.
  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    _syncSearchField(_controller.state.searchText);
  }

  /// Requests the next page as the end of the list comes into view.
  ///
  /// Prefetching on approach rather than on arrival means the next page is
  /// usually already there by the time the buyer reaches the bottom. The
  /// controller's own guards make the repeated calls that threshold produces
  /// harmless.
  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }

    final ScrollPosition position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 320) {
      _controller.loadMore();
    }
  }

  /// Keeps the field in step when the search is cleared from elsewhere — the
  /// empty state's "Clear search and filters" button, for instance — without
  /// fighting the user's cursor while they type.
  void _syncSearchField(String value) {
    if (value == _searchField.text) {
      return;
    }
    _searchField.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  Future<void> _openFilters(MarketplaceState state) async {
    final ListingFilters? applied = await showMarketplaceFilterScreen(
      context: context,
      filters: state.filters,
    );

    if (!mounted || applied == null) {
      return;
    }
    await _controller.applyFilters(applied);
    if (mounted) {
      _scrollToTop();
    }
  }

  /// Returns to the top of the list after the query changed.
  ///
  /// Without this, applying a filter from page 3 leaves the buyer looking at a
  /// scroll offset far beyond the new, much shorter result set — often past its
  /// end, showing blank space.
  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  /// Applies one Browse category to the shared marketplace filter.
  ///
  /// A tap is a filter change like any other: the controller resets pagination
  /// and issues one request. Re-tapping the selected chip is a no-op.
  Future<void> _selectCategory(String? value) async {
    final String next = (value ?? '').trim();
    if (next == _controller.state.filters.livestockType) {
      return;
    }

    await _controller.applyFilters(
      _controller.state.filters.copyWith(livestockType: next),
    );
    if (mounted) {
      _scrollToTop();
    }
  }

  /// Removes only the category filter, keeping search and the other filters.
  Future<void> _clearCategory() => _selectCategory(null);

  /// Clears the search term, the category and every other filter, then reloads
  /// once. This is the field's X: one request that restores all listings.
  Future<void> _clearSearchAndFilters() async {
    _searchField.clear();
    await _controller.clearSearchAndFilters();
    if (mounted) {
      _scrollToTop();
    }
  }

  /// Clears both the search term and the filters, then reloads.
  ///
  /// One request, not two: the search text and the filters are a single query,
  /// so committing them separately would render the intermediate result set the
  /// user never asked to see.
  Future<void> _clearEverything() async {
    _searchField.clear();
    await _controller.clearSearchAndFilters();
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
    return Scaffold(
      appBar: AppBar(title: const Text('Marketplace')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (BuildContext context, Widget? child) {
            final MarketplaceState state = _controller.state;

            return Column(
              children: <Widget>[
                _SearchAndFilters(
                  controller: _controller,
                  searchField: _searchField,
                  state: state,
                  onOpenFilters: () => _openFilters(state),
                  onClearSearch: _clearSearchAndFilters,
                  onSelectCategory: _selectCategory,
                  onClearCategory: _clearCategory,
                ),
                const Divider(height: 1),
                Expanded(child: _body(state)),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Chooses between the list and the states that replace it.
  Widget _body(MarketplaceState state) {
    if (state.showsBlockingState) {
      if (state.status == MarketplaceStatus.failed) {
        return MarketplaceErrorState(
          message: state.errorMessage ?? 'Something went wrong.',
          onRetry: _controller.retry,
        );
      }
      return const _LoadingList();
    }

    if (state.isEmpty) {
      return MarketplaceEmptyState(
        isFiltered: state.hasActiveQuery,
        onClear: state.hasActiveQuery ? _clearEverything : null,
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double spacing = AppSpacing.sm;
        final double availableWidth =
            constraints.maxWidth - (AppSpacing.screenGutter * 2);
        final double itemWidth = (availableWidth - spacing) / 2;
        // Photo band (4:3, as the card draws it) plus the text block below
        // it. A single extent keeps both columns pixel-aligned regardless of
        // how much text a seller wrote.
        final double itemExtent = (itemWidth * 3 / 4) + _cardTextHeight;

        return RefreshIndicator(
          // Pull-to-refresh keeps the current results mounted: `refresh` publishes
          // `refreshing`, which is not a blocking state, so the grid below stays
          // visible and the indicator itself is what communicates the request.
          onRefresh: _controller.refresh,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              if (state.refreshErrorMessage != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenGutter,
                    AppSpacing.sm,
                    AppSpacing.screenGutter,
                    0,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: PagedListRefreshNotice(
                      message:
                          'Could not refresh. ${state.refreshErrorMessage}',
                      onRetry: () => unawaited(_controller.refresh()),
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
                      onTap: () => _openListing(listing),
                    );
                  }, childCount: state.listings.length),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenGutter,
                    AppSpacing.sm,
                    AppSpacing.screenGutter,
                    0,
                  ),
                  child: PagedListLoadMoreFooter(
                    isLoading: state.status == MarketplaceStatus.loadingMore,
                    hasMore: state.hasMorePages,
                    errorMessage: state.loadMoreErrorMessage,
                    onLoadMore: _controller.loadMore,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The search field and the filter control, above the list.
class _SearchAndFilters extends StatelessWidget {
  const _SearchAndFilters({
    required this.controller,
    required this.searchField,
    required this.state,
    required this.onOpenFilters,
    required this.onClearSearch,
    required this.onSelectCategory,
    required this.onClearCategory,
  });

  final MarketplaceController controller;
  final TextEditingController searchField;
  final MarketplaceState state;
  final VoidCallback onOpenFilters;
  final VoidCallback onClearSearch;
  final ValueChanged<String?> onSelectCategory;
  final VoidCallback onClearCategory;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.sm,
        AppSpacing.screenGutter,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: searchField,
                  textInputAction: TextInputAction.search,
                  onChanged: controller.updateSearch,
                  // Committing from the keyboard skips the remaining debounce. On a
                  // slow connection that is the difference between results now and
                  // results a moment later.
                  onSubmitted: (String _) => controller.submitSearch(),
                  decoration: InputDecoration(
                    hintText: 'Search livestock',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    contentPadding: AppInputs.plainPadding,
                    suffixIcon: state.searchText.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Clear search and filters',
                            onPressed: onClearSearch,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              MarketplaceFilterButton(state: state, onPressed: onOpenFilters),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // Directly below the search bar, per the Browse prototype. These
          // chips drive the same exact-match `livestock_type` filter as the
          // Filter screen, so the two can never disagree.
          _BrowseCategoryChips(
            selected: state.filters.livestockType.trim(),
            onSelect: onSelectCategory,
          ),
          if (state.filters.livestockType.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            _ActiveCategoryIndicator(
              label: _BrowseCategory.labelFor(
                state.filters.livestockType.trim(),
              ),
              onClear: onClearCategory,
            ),
          ],
        ],
      ),
    );
  }
}

/// The five Browse categories, matching the Filter screen's Animal Type tiles.
class _BrowseCategory {
  const _BrowseCategory(this.label, this.value);

  final String label;

  /// `null` is "All" — no `livestock_type` filter.
  final String? value;

  /// The chip label for a filter value; an unknown value is shown as typed.
  static String labelFor(String value) {
    for (final _BrowseCategory category in values) {
      if (category.value == value) {
        return category.label;
      }
    }
    return value;
  }

  static const List<_BrowseCategory> values = <_BrowseCategory>[
    _BrowseCategory('All', null),
    _BrowseCategory('Cattle', 'cattle'),
    _BrowseCategory('Swine', 'swine'),
    _BrowseCategory('Goat', 'goat'),
    _BrowseCategory('Carabao', 'carabao'),
  ];
}

/// A horizontally scrollable chip row. Selecting a chip applies its
/// `livestock_type`; "All" clears it. The selected chip is derived from the
/// shared filter state, so a selection made on Home or in the Filter screen is
/// reflected here without any extra request.
class _BrowseCategoryChips extends StatelessWidget {
  const _BrowseCategoryChips({required this.selected, required this.onSelect});

  final String selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _BrowseCategory.values.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: AppSpacing.xs),
        itemBuilder: (BuildContext context, int index) {
          final _BrowseCategory category = _BrowseCategory.values[index];
          final bool isSelected = category.value == null
              ? selected.isEmpty
              : selected.toLowerCase() == category.value!.toLowerCase();

          return ChoiceChip(
            key: ValueKey<String>(
              'browse-category-${category.value?.toLowerCase() ?? 'all'}',
            ),
            label: Text(category.label),
            selected: isSelected,
            showCheckmark: false,
            onSelected: (_) => onSelect(category.value),
          );
        },
      ),
    );
  }
}

/// The active category, stated beside the search field and removable without
/// opening the Filter screen.
class _ActiveCategoryIndicator extends StatelessWidget {
  const _ActiveCategoryIndicator({required this.label, required this.onClear});

  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      key: const ValueKey<String>('active-category-filter'),
      label: Text('Category: $label'),
      onDeleted: onClear,
      deleteIcon: const Icon(Icons.close, size: 18),
      deleteButtonTooltipMessage: 'Remove category filter',
    );
  }
}

/// Placeholder rows for the first load.
///
/// Skeleton cards rather than a bare spinner, so the list's structure is
/// visible while it loads and the content does not jump when it arrives. They
/// are non-interactive: a card that cannot be opened should not look tappable.
class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double spacing = AppSpacing.sm;
        final double availableWidth =
            constraints.maxWidth - (AppSpacing.screenGutter * 2);
        final double itemWidth = (availableWidth - spacing) / 2;

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.md,
            AppSpacing.screenGutter,
            0,
          ),
          physics: const AlwaysScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            mainAxisExtent: (itemWidth * 3 / 4) + _cardTextHeight,
          ),
          itemCount: 4,
          itemBuilder: (BuildContext context, int index) =>
              const _SkeletonCard(),
        );
      },
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(color: AppColors.background),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _Bar(width: 54),
                const SizedBox(height: AppSpacing.xs),
                const _Bar(width: 110),
                const SizedBox(height: AppSpacing.xs),
                const _Bar(width: 80),
                const SizedBox(height: AppSpacing.sm),
                const _Bar(width: 96),
              ],
            ),
          ),
        ],
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
