import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../models/listing.dart';
import '../../../models/marketplace_page.dart';
import '../../../repositories/marketplace_repository.dart';
import 'listing_filters.dart';
import 'marketplace_state.dart';

/// Presentation logic for the marketplace list.
///
/// The only thing that mutates [state]. The screen calls these methods and
/// listens; it never touches the repository or `ApiClient` itself.
///
/// ## Three problems this class exists to solve
///
/// **Requests per keystroke.** Typing "holstein" must not be six requests.
/// [updateSearch] records the text and starts a debounce; the request happens
/// once typing pauses, or immediately via [submitSearch] when the user commits
/// with the keyboard.
///
/// **Overlapping responses.** Typing "h", pausing, then "ho" starts a second
/// request while the first may still be in flight. If they resolve out of order
/// the screen would render results for "h" under a field containing "ho". Every
/// first-page request takes a generation number and a response is applied only
/// if its generation is still the newest, so a stale answer is discarded rather
/// than displayed.
///
/// **Duplicate work.** [loadMore] is guarded by status, so scrolling the end of
/// the list cannot fire the same page twice, and the controller stops asking
/// once the server says there is no next page.
///
/// **A refresh that throws away the results.** [refresh] re-queries page 1 while
/// keeping what is on screen, so pulling to refresh never blanks a list the user
/// is reading, and a failed refresh leaves the stale-but-valid results in place
/// with a notice instead of replacing them with an error screen.
///
/// ## Errors
///
/// [ApiException.message] is already safe to display, so failures are published
/// as-is rather than re-worded. A `401` is *not* special-cased here: the token
/// has been cleared by then and the auth gate takes the app to sign-in, so
/// writing a "session expired" message into the list would only flash.
class MarketplaceController extends ChangeNotifier {
  MarketplaceController(this._repository);

  /// How long typing must pause before the list is re-queried.
  ///
  /// Long enough that a normal word costs one request, short enough that the
  /// list does not feel stuck behind the keyboard.
  static const Duration searchDebounce = Duration(milliseconds: 350);

  final MarketplaceRepository _repository;

  MarketplaceState _state = const MarketplaceState();
  MarketplaceState get state => _state;

  Timer? _searchDebounce;
  bool _disposed = false;

  /// Incremented for every first-page request. A response whose generation is
  /// stale is thrown away.
  int _generation = 0;

  /// Guards against a second page request while one is in flight.
  bool _loadingMore = false;

  /// The query of the first-page request currently in flight, or `null`.
  ///
  /// Lets [loadInitial] be idempotent without blocking the calls that *should*
  /// interrupt it. The marketplace screen calls `loadInitial` from `initState`,
  /// and a rebuild that re-enters it must not cost a second request; but a
  /// changed search term or a new filter genuinely has to supersede whatever is
  /// in flight, and a blanket in-flight guard would silently swallow it.
  String? _inFlightFirstPageQuery;

  /// Loads the first page, unless that exact query is already being fetched.
  ///
  /// Safe to call repeatedly: a duplicate request for the same query is a no-op,
  /// while a request for a *different* query replaces the one in flight and the
  /// older response is discarded.
  Future<void> loadInitial() {
    final String query = _firstPageQuery;
    if (_inFlightFirstPageQuery == query) {
      return Future<void>.value();
    }
    return _loadFirstPage();
  }

  /// Re-queries the first page, keeping the current search and filters.
  ///
  /// This is the error state's retry: there is nothing on screen to preserve, so
  /// the request is a normal blocking first-page load and a failure produces the
  /// full-screen error again. It always re-requests, even if the same query is
  /// somehow in flight, because a deliberate retry is a request the user asked
  /// for.
  Future<void> retry() => _loadFirstPage();

  /// Pull-to-refresh: re-queries page 1 **without** clearing the list.
  ///
  /// The user is already looking at results and has only asked for fresher ones,
  /// so the current cards stay on screen and are swapped when the response lands.
  /// Blanking them for a second would be a worse experience than being briefly
  /// stale, and a refresh that fails leaves the stale-but-valid results in place
  /// with [MarketplaceState.refreshErrorMessage] rather than an error screen.
  ///
  /// Falls back to [retry] when there is nothing to preserve, so the very first
  /// pull of an empty list still shows a blocking load.
  Future<void> refresh() async {
    // A request for page 1 is already in flight. It will produce exactly what a
    // refresh would, so starting a second one is pure waste — and cancelling the
    // first would discard a request the user is already waiting on.
    if (_state.status == MarketplaceStatus.loading ||
        _state.status == MarketplaceStatus.refreshing) {
      return;
    }

    // Nothing worth preserving: an ordinary blocking first-page load, which is
    // also the right outcome for a retry after a failure.
    if (_state.status == MarketplaceStatus.initial ||
        _state.status == MarketplaceStatus.failed ||
        _state.listings.isEmpty) {
      await retry();
      return;
    }

    await _loadFirstPage(keepResults: true);
  }

  /// Records new search text and schedules a debounced request.
  ///
  /// No request is made here — the field updates immediately so typing stays
  /// responsive, and the server is asked once the user pauses.
  void updateSearch(String value) {
    if (_state.searchText == value) {
      return;
    }

    _set(_state.copyWith(searchText: value));
    _scheduleSearch();
  }

  /// Applies the search text immediately, cancelling any pending debounce.
  ///
  /// Called when the user commits from the keyboard, and by the field's clear
  /// button, so that clearing the search refreshes the list at once instead of
  /// after a further pause.
  Future<void> submitSearch() async {
    _searchDebounce?.cancel();
    _searchDebounce = null;
    await _loadFirstPage();
  }

  /// Applies a new filter selection and reloads from page 1.
  ///
  /// Pagination is always reset: keeping page 3 of the previous result set while
  /// showing filters for a different query would be meaningless.
  ///
  /// Re-applying an identical selection is a no-op rather than a request.
  Future<void> applyFilters(ListingFilters next) async {
    if (next == _state.filters) {
      return;
    }
    _set(_state.copyWith(filters: next));
    await _loadFirstPage();
  }

  /// Clears all filters and reloads from page 1.
  Future<void> clearFilters() => applyFilters(ListingFilters.none);

  /// Clears the search term *and* the filters in a single request.
  ///
  /// The empty-state "clear everything" control needs to widen the query, not
  /// just the filters. Doing that with [submitSearch] followed by
  /// [clearFilters] would issue two sequential requests and briefly render the
  /// first one's results, so both are committed before the one load.
  Future<void> clearSearchAndFilters() async {
    if (_state.searchText.isEmpty && !_state.filters.isActive) {
      return;
    }
    _searchDebounce?.cancel();
    _searchDebounce = null;
    _set(_state.copyWith(searchText: '', filters: ListingFilters.none));
    await _loadFirstPage();
  }

  /// Loads the next page and appends it to what is already on screen.
  ///
  /// Does nothing when a page is already loading, when the first page has not
  /// succeeded yet, or when the server has reported no further pages.
  Future<void> loadMore() async {
    if (_loadingMore ||
        _state.status == MarketplaceStatus.loading ||
        _state.status == MarketplaceStatus.initial ||
        _state.status == MarketplaceStatus.refreshing ||
        _state.status == MarketplaceStatus.failed ||
        _state.listings.isEmpty ||
        !_state.hasMorePages) {
      return;
    }

    _loadingMore = true;
    final int generation = _generation;
    _set(
      _state.copyWith(
        status: MarketplaceStatus.loadingMore,
        clearLoadMoreError: true,
      ),
    );

    try {
      final MarketplacePage page = await _repository.browse(
        search: _state.searchText,
        livestockType: _state.filters.livestockType,
        minPrice: _state.filters.minPrice,
        maxPrice: _state.filters.maxPrice,
        page: _state.currentPage + 1,
      );

      // A first-page request started while this one was in flight: the user's
      // query changed, so these results are for a question they have moved on
      // from. Dropping them is what stops a stale page overwriting fresh
      // results.
      if (_disposed || generation != _generation) {
        return;
      }

      _set(
        _state.copyWith(
          status: MarketplaceStatus.ready,
          listings: <Listing>[..._state.listings, ...page.listings],
          pagination: page.pagination,
        ),
      );
    } on ApiException catch (error) {
      if (_disposed || generation != _generation) {
        return;
      }
      // The listings already loaded are still valid and still on screen. Only
      // the "load more" affordance reports the failure.
      _set(
        _state.copyWith(
          status: MarketplaceStatus.ready,
          loadMoreErrorMessage: error.message,
        ),
      );
    } on Object {
      if (_disposed || generation != _generation) {
        return;
      }
      _set(
        _state.copyWith(
          status: MarketplaceStatus.ready,
          loadMoreErrorMessage:
              'Could not load more listings. Please try again.',
        ),
      );
    } finally {
      _loadingMore = false;
    }
  }

  void _scheduleSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(searchDebounce, () {
      _searchDebounce = null;
      // Fire-and-forget: the state carries the outcome, and a failure must not
      // become an unhandled async error.
      unawaited(_loadFirstPage());
    });
  }

  /// A stable string for the query a first-page request would send.
  ///
  /// Used only to recognise a duplicate request, so it has to capture everything
  /// that changes the response and nothing that does not.
  String get _firstPageQuery =>
      '${_state.searchText}|${_state.filters.livestockType}|'
      '${_state.filters.minPrice}|${_state.filters.maxPrice}|1';

  /// Requests page 1 and replaces everything on screen with the result.
  ///
  /// With [keepResults] the existing listings survive the request instead of
  /// being cleared up front. That is the only difference, and it changes both
  /// the published status and what a failure does: a refresh that fails leaves
  /// the user with the results they had plus a notice, where a normal load that
  /// fails has nothing to fall back to and becomes [MarketplaceStatus.failed].
  Future<void> _loadFirstPage({bool keepResults = false}) async {
    _searchDebounce?.cancel();
    _searchDebounce = null;

    final int generation = ++_generation;
    final String query = _firstPageQuery;
    _inFlightFirstPageQuery = query;

    _set(
      _state.copyWith(
        status: keepResults
            ? MarketplaceStatus.refreshing
            : MarketplaceStatus.loading,
        // Cleared up front: a stale page total or "no results" message must not
        // survive into a request that is about to replace it.
        clearListings: !keepResults,
        clearError: true,
        clearLoadMoreError: true,
        clearRefreshError: true,
      ),
    );

    try {
      final MarketplacePage page = await _repository.browse(
        search: _state.searchText,
        livestockType: _state.filters.livestockType,
        minPrice: _state.filters.minPrice,
        maxPrice: _state.filters.maxPrice,
        page: 1,
      );

      if (_disposed || generation != _generation) {
        return;
      }

      _inFlightFirstPageQuery = null;
      _set(
        _state.copyWith(
          status: MarketplaceStatus.ready,
          listings: page.listings,
          pagination: page.pagination,
        ),
      );
    } on ApiException catch (error) {
      if (_disposed || generation != _generation) {
        return;
      }
      _inFlightFirstPageQuery = null;
      _set(
        keepResults
            ? _state.copyWith(
                status: MarketplaceStatus.ready,
                refreshErrorMessage: error.message,
              )
            : _state.copyWith(
                status: MarketplaceStatus.failed,
                errorMessage: error.message,
              ),
      );
    } on Object {
      if (_disposed || generation != _generation) {
        return;
      }
      _inFlightFirstPageQuery = null;
      final String message = 'Something went wrong. Please try again.';
      _set(
        keepResults
            ? _state.copyWith(
                status: MarketplaceStatus.ready,
                refreshErrorMessage: message,
              )
            : _state.copyWith(
                status: MarketplaceStatus.failed,
                errorMessage: message,
              ),
      );
    }
  }

  void _set(MarketplaceState next) {
    if (_disposed) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _searchDebounce?.cancel();
    _searchDebounce = null;
    super.dispose();
  }
}
