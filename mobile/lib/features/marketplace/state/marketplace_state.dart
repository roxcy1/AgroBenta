import '../../../models/listing.dart';
import '../../../models/pagination.dart';
import 'listing_filters.dart';

/// Where the marketplace list is in its lifecycle.
///
/// One enum for the whole screen, because these are mutually exclusive
/// presentations: a screen showing an error is not also showing results, and a
/// screen fetching page 3 is not in the same state as one fetching page 1.
/// Modelling them as booleans (`isLoading`, `isLoadingMore`, `hasError`) is how
/// a list ends up rendering a spinner and an error message at once.
enum MarketplaceStatus {
  /// Constructed but nothing requested yet.
  ///
  /// Distinct from [loading] only so the very first frame can be told apart
  /// from a request in progress; the screen renders both the same way.
  initial,

  /// The first page is in flight and there is nothing to show yet.
  loading,

  /// At least one page is loaded. The screen may still be fetching another.
  ready,

  /// A page after the first is in flight, and the results already on screen
  /// stay there.
  ///
  /// Separate from [loading] so the UI shows a small indicator at the bottom of
  /// a populated list instead of replacing the list with a spinner.
  loadingMore,

  /// Page 1 is being re-queried while results are already on screen.
  ///
  /// This is pull-to-refresh, and it is the one first-page request that must not
  /// blank the screen: the user is looking at listings and has merely asked for
  /// fresher ones, so the current results stay and are swapped when the response
  /// arrives. If it fails, [refreshing] returns to [ready] with the stale results
  /// and a notice rather than replacing the screen with an error — there is
  /// still something worth showing.
  refreshing,

  /// The first page failed. There is nothing on screen to preserve.
  failed,
}

/// An immutable snapshot of everything the marketplace list renders from.
///
/// The screen reads this and nothing else. It never asks the repository
/// directly, and it never infers a state the controller did not publish — the
/// difference between "no listings" and "no listings *for this search*" is a
/// real distinction to a user, so it is carried here rather than guessed in a
/// widget.
class MarketplaceState {
  const MarketplaceState({
    this.status = MarketplaceStatus.initial,
    this.listings = const <Listing>[],
    this.pagination,
    this.filters = ListingFilters.none,
    this.searchText = '',
    this.errorMessage,
    this.loadMoreErrorMessage,
    this.refreshErrorMessage,
  });

  final MarketplaceStatus status;

  /// Every listing loaded so far, in server order. Accumulates across pages.
  final List<Listing> listings;

  /// Pagination for the most recent page received. `null` before the first
  /// successful response.
  final Pagination? pagination;

  /// The filter selection currently reflected in [listings].
  final ListingFilters filters;

  /// What the search field shows, which is not always what has been searched
  /// for: the user may be mid-type while the last debounce is still pending.
  final String searchText;

  /// A displayable failure for the whole screen. Set only in
  /// [MarketplaceStatus.failed].
  final String? errorMessage;

  /// A displayable failure for a *subsequent* page.
  ///
  /// Deliberately separate from [errorMessage]. A page-3 request failing must
  /// not discard the listings already on screen, and it must not cover them with
  /// a full-screen error either — the user keeps what they had and gets a
  /// message with a retry.
  final String? loadMoreErrorMessage;

  /// A displayable failure for a re-query of the first page that kept the
  /// existing listings, i.e. a pull-to-refresh that did not succeed.
  ///
  /// The third failure slot, and the reason it cannot share [errorMessage] or
  /// [loadMoreErrorMessage]: the results on screen are still valid, the server
  /// has not produced a next page, and the user's own action failed. The retry
  /// belongs to the refresh, not to the list.
  final String? refreshErrorMessage;

  /// 1-based page currently displayed, or 0 before anything has loaded.
  int get currentPage => pagination?.currentPage ?? 0;

  /// Whether the server has another page.
  bool get hasMorePages => pagination?.hasNextPage ?? false;

  /// Loaded, but with no listings. The screen distinguishes this from
  /// [MarketplaceStatus.failed] and from a first load still in progress.
  bool get isEmpty =>
      status == MarketplaceStatus.ready && listings.isEmpty;

  /// Whether this list is narrowed by a search or a filter.
  ///
  /// Drives the wording of the empty state: "No active listings yet" is a
  /// statement about the marketplace, while "No listings match your search" is
  /// a statement about the query, and only the second one should offer to clear
  /// it.
  bool get hasActiveQuery => searchText.trim().isNotEmpty || filters.isActive;

  /// A request is in flight — either the first page or a later one.
  bool get isBusy =>
      status == MarketplaceStatus.loading ||
      status == MarketplaceStatus.loadingMore ||
      status == MarketplaceStatus.refreshing;

  /// The whole list is replaced by a loading or error state. True only for a
  /// first page with nothing to preserve.
  bool get showsBlockingState =>
      status == MarketplaceStatus.loading || status == MarketplaceStatus.failed;

  MarketplaceState copyWith({
    MarketplaceStatus? status,
    List<Listing>? listings,
    Pagination? pagination,
    ListingFilters? filters,
    String? searchText,
    String? errorMessage,
    String? loadMoreErrorMessage,
    String? refreshErrorMessage,
    bool clearError = false,
    bool clearLoadMoreError = false,
    bool clearRefreshError = false,
    bool clearListings = false,
  }) {
    return MarketplaceState(
      status: status ?? this.status,
      listings: clearListings ? const <Listing>[] : (listings ?? this.listings),
      pagination: pagination ?? this.pagination,
      filters: filters ?? this.filters,
      searchText: searchText ?? this.searchText,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      loadMoreErrorMessage: clearLoadMoreError
          ? null
          : (loadMoreErrorMessage ?? this.loadMoreErrorMessage),
      refreshErrorMessage: clearRefreshError
          ? null
          : (refreshErrorMessage ?? this.refreshErrorMessage),
    );
  }

  @override
  String toString() =>
      'MarketplaceState(${status.name}, ${listings.length} listings, '
      'page $currentPage, filters: $filters)';
}
