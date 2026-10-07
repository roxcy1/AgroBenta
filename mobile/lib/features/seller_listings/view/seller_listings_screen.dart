import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/listing.dart';
import '../state/seller_listing_controller.dart';
import '../state/seller_listing_scope.dart';
import '../state/seller_listing_state.dart';
import '../view/seller_listing_views.dart';
import '../widgets/seller_listing_card.dart';
import 'seller_listing_detail_screen.dart';
import 'seller_listing_form_screen.dart';

/// The seller's own listings: "My Listings".
///
/// The one screen a seller lands on to manage what they have put up, and the
/// entry point for creating a listing. Reached from Home, not from the bottom
/// navigation — `mobile/DESIGN.md` forbids building navigation for screens a
/// buyer cannot use, and My Listings is unreachable for a buyer by definition
/// (the server answers `403`).
///
/// A plain [StatefulWidget] rather than a `Consumer` on a provider: it reads the
/// controller once in `initState` and rebuilds from [ListenableBuilder], so a
/// keystroke in the search field does not rebuild the list of cards.
class SellerListingsScreen extends StatefulWidget {
  const SellerListingsScreen({super.key});

  @override
  State<SellerListingsScreen> createState() => _SellerListingsScreenState();
}

class _SellerListingsScreenState extends State<SellerListingsScreen> {
  late final SellerListingController _controller;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchField = TextEditingController();

  @override
  void initState() {
    super.initState();
    // `readOf`, not `of`: the dependency is not needed here, and the whole
    // screen is already listening to the controller directly.
    _controller = SellerListingScope.readOf(context);
    _controller.loadInitial();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _searchField.dispose();
    super.dispose();
  }

  /// Requests the next page when the list is scrolled near its end.
  ///
  /// The controller ignores the call unless page 1 has arrived and the server has
  /// said there is more, so a short list that cannot fill the viewport never
  /// fires it.
  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final ScrollPosition position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      _controller.loadMore();
    }
  }

  void _openDetail(Listing listing) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            SellerListingDetailScreen(listing: listing),
      ),
    );
  }

  Future<void> _openCreate() async {
    final Listing? created = await Navigator.of(context).push<Listing>(
      MaterialPageRoute<Listing>(
        builder: (BuildContext context) => const SellerListingFormScreen(),
        fullscreenDialog: true,
      ),
    );

    if (!mounted || created == null) {
      return;
    }
    // The controller already merged the created draft into the list; opening its
    // detail takes the seller to where they can read the draft back and submit
    // it, which is the point of having just created it.
    _openDetail(created);
  }

  Future<void> _confirmDelete(Listing listing) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete this listing?'),
        content: Text(
          '"${listing.title}" will be removed permanently. This cannot be '
          'undone. If you only want to stop it appearing in the marketplace, '
          'ask an administrator to deactivate it instead.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }
    await _controller.delete(listing.id);
  }

  Future<void> _confirmSubmit(Listing listing) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Submit for review?'),
        content: const Text(
          'An administrator will review this listing. Once submitted you cannot '
          'change or resubmit it yourself.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Submit for review'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }
    await _controller.submit(listing.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Listings'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              0,
              AppSpacing.screenGutter,
              AppSpacing.sm,
            ),
            child: TextField(
              controller: _searchField,
              onChanged: _controller.updateSearch,
              onSubmitted: (_) => _controller.submitSearch(),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search your listings',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                suffixIcon: ListenableBuilder(
                  listenable: _controller,
                  builder: (BuildContext context, Widget? child) =>
                      _controller.state.searchText.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchField.clear();
                            _controller.clearQuery();
                          },
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.add),
        label: const Text('Create listing'),
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (BuildContext context, Widget? child) {
          final SellerListingState state = _controller.state;

          return Column(
            children: <Widget>[
              _StatusFilterBar(
                selected: state.statusFilter,
                onSelected: _controller.applyStatusFilter,
              ),
              if (state.conflictMessage != null ||
                  state.actionErrorMessage != null) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenGutter,
                    0,
                    AppSpacing.screenGutter,
                    AppSpacing.sm,
                  ),
                  child: state.conflictMessage != null
                      ? ListingConflictNotice(message: state.conflictMessage!)
                      : ListingActionErrorBanner(
                          message: state.actionErrorMessage!,
                        ),
                ),
              ],
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _controller.refresh,
                  child: switch (state.status) {
                    SellerListingStatus.initial ||
                    SellerListingStatus.loading => const Center(
                      child: CircularProgressIndicator(),
                    ),
                    // A scroll view even on a full-screen error, so
                    // pull-to-refresh works there as well as on the list.
                    SellerListingStatus.failed => ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: <Widget>[
                        SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.5,
                          child: SellerListingsErrorState(
                            message:
                                state.errorMessage ?? 'Something went wrong.',
                            onRetry: _controller.retry,
                          ),
                        ),
                      ],
                    ),
                    _ when state.listings.isEmpty => ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: <Widget>[
                        SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.5,
                          child: SellerListingsEmptyState(
                            isFiltered: state.hasActiveQuery,
                            onCreate: _openCreate,
                            onClear: _controller.clearQuery,
                          ),
                        ),
                      ],
                    ),
                    _ => _ListingList(
                      state: state,
                      controller: _controller,
                      scrollController: _scrollController,
                      onOpen: _openDetail,
                      onSubmit: _confirmSubmit,
                      onDelete: _confirmDelete,
                    ),
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The list itself, with the load-more footer.
class _ListingList extends StatelessWidget {
  const _ListingList({
    required this.state,
    required this.controller,
    required this.scrollController,
    required this.onOpen,
    required this.onSubmit,
    required this.onDelete,
  });

  final SellerListingState state;
  final SellerListingController controller;
  final ScrollController scrollController;
  final ValueChanged<Listing> onOpen;
  final ValueChanged<Listing> onSubmit;
  final ValueChanged<Listing> onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      controller: scrollController,
      // Always scrollable so pull-to-refresh works even on a list of two.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.sm,
        AppSpacing.screenGutter,
        96,
      ),
      itemCount: state.listings.length + 1,
      separatorBuilder: (BuildContext context, int index) =>
          const SizedBox(height: AppSpacing.sm),
      itemBuilder: (BuildContext context, int index) {
        if (index == state.listings.length) {
          return _ListFooter(state: state, onLoadMore: controller.loadMore);
        }

        final Listing listing = state.listings[index];
        return SellerListingCard(
          listing: listing,
          busy: state.isActioning && state.actionListingId == listing.id,
          onTap: () => onOpen(listing),
          onSubmit: () => onSubmit(listing),
          // The row's context, which is a descendant of the `Navigator`. A
          // `StatelessWidget` has no `context` of its own to reach for, and
          // holding the enclosing `State`'s would outlive the row.
          onEdit: () => Navigator.of(context).push<Listing>(
            MaterialPageRoute<Listing>(
              builder: (BuildContext context) =>
                  SellerListingFormScreen(listing: listing),
              fullscreenDialog: true,
            ),
          ),
          onDelete: () => onDelete(listing),
        );
      },
    );
  }
}

/// The list's last row: a page spinner, a "load more" failure, a result count, or
/// the end-of-list mark.
class _ListFooter extends StatelessWidget {
  const _ListFooter({required this.state, required this.onLoadMore});

  final SellerListingState state;

  /// Handed down rather than looked up: the enclosing [ListenableBuilder] owns
  /// the controller and this widget deliberately does not depend on the scope, so
  /// it must be given the callback.
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int total = state.pagination?.total ?? state.listings.length;

    if (state.status == SellerListingStatus.loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (state.loadMoreErrorMessage != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          children: <Widget>[
            Text(
              state.loadMoreErrorMessage!,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            OutlinedButton(
              onPressed: onLoadMore,
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Text(
        state.hasMorePages || state.listings.length < total
            ? 'Showing ${state.listings.length} of $total'
            : 'All $total listings',
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// The status filter chips, "All" first.
class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({required this.selected, required this.onSelected});

  final ListingStatus? selected;
  final ValueChanged<ListingStatus?> onSelected;

  /// Every status, in the order a seller's listings move through them, plus the
  /// terminal states last. "All" is first because it is the default view.
  static const List<ListingStatus?> _filters = <ListingStatus?>[
    null,
    ListingStatus.draft,
    ListingStatus.pending,
    ListingStatus.active,
    ListingStatus.sold,
    ListingStatus.inactive,
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenGutter,
        ),
        itemCount: _filters.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: AppSpacing.xs),
        itemBuilder: (BuildContext context, int index) {
          final ListingStatus? status = _filters[index];
          final bool isSelected = status == selected;
          final String label = status == null
              ? 'All'
              : listingStatusLabel(status);

          return Center(
            child: ChoiceChip(
              label: Text(label),
              selected: isSelected,
              showCheckmark: false,
              onSelected: (bool value) {
                if (value) {
                  onSelected(status);
                }
              },
            ),
          );
        },
      ),
    );
  }
}
