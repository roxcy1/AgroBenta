import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/listing.dart';
import '../state/listing_filters.dart';
import '../state/marketplace_controller.dart';
import '../state/marketplace_scope.dart';
import '../state/marketplace_state.dart';
import '../widgets/listing_card.dart';
import '../widgets/marketplace_state_views.dart';
import 'listing_detail_screen.dart';
import 'marketplace_filter_sheet.dart';

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
    final ListingFilters? applied = await showMarketplaceFilterSheet(
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
        builder: (BuildContext context) => ListingDetailScreen(listingId: listing.id),
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

    return RefreshIndicator(
      // Pull-to-refresh keeps the current results mounted: `refresh` publishes
      // `refreshing`, which is not a blocking state, so the list below stays
      // visible and the indicator itself is what communicates the request.
      onRefresh: _controller.refresh,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          AppSpacing.md,
          AppSpacing.screenGutter,
          0,
        ),
        itemCount:
            state.listings.length + 1 + (state.refreshErrorMessage != null ? 1 : 0),
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(height: AppSpacing.sm),
        itemBuilder: (BuildContext context, int index) {
          if (state.refreshErrorMessage != null && index == 0) {
            return RefreshFailedNotice(
              message: 'Could not refresh. ${state.refreshErrorMessage}',
              onRetry: () => unawaited(_controller.refresh()),
            );
          }

          final int listingIndex =
              index - (state.refreshErrorMessage != null ? 1 : 0);

          if (listingIndex == state.listings.length) {
            return LoadMoreFooter(
              isLoading: state.status == MarketplaceStatus.loadingMore,
              hasMore: state.hasMorePages,
              errorMessage: state.loadMoreErrorMessage,
              onLoadMore: _controller.loadMore,
            );
          }

          final Listing listing = state.listings[listingIndex];
          return ListingCard(
            listing: listing,
            onTap: () => _openListing(listing),
          );
        },
      ),
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
  });

  final MarketplaceController controller;
  final TextEditingController searchField;
  final MarketplaceState state;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.sm,
        AppSpacing.screenGutter,
        AppSpacing.sm,
      ),
      child: Row(
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
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: state.searchText.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Clear search',
                        onPressed: () {
                          searchField.clear();
                          controller.submitSearch();
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          _FilterButton(state: state, onPressed: onOpenFilters),
        ],
      ),
    );
  }
}

/// The filter control, badged when filters are active.
///
/// A button, not a permanently visible row of every filter. Six filters would
/// not fit on a phone, and a list that only grows as more filters are added
/// would push the results off the screen. The summary in the tooltip covers
/// what is applied for anyone who wants the detail without opening the sheet.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.state, required this.onPressed});

  final MarketplaceState state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String summary = state.filters.summary;
    final bool isActive = state.filters.isActive;

    return Tooltip(
      message: isActive ? 'Filters: $summary' : 'Filters',
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          side: BorderSide(
            color: isActive ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.tune, size: 20),
            if (isActive) ...<Widget>[
              const SizedBox(width: AppSpacing.xxs),
              // A count, not the values: the sheet shows the values, and the
              // count is what fits.
              Text(
                '${state.filters.activeCount}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ],
          ],
        ),
      ),
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
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.md,
        AppSpacing.screenGutter,
        0,
      ),
      itemCount: 4,
      separatorBuilder: (BuildContext context, int index) =>
          const SizedBox(height: AppSpacing.sm),
      itemBuilder: (BuildContext context, int index) => const _SkeletonCard(),
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border.all(color: AppColors.border),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _Bar(width: 90),
                  const SizedBox(height: AppSpacing.xs),
                  _Bar(width: 160),
                  const SizedBox(height: AppSpacing.md),
                  _Bar(width: 110),
                ],
              ),
            ),
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
