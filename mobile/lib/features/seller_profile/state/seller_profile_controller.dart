import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../models/listing.dart';
import '../../../models/marketplace_page.dart';
import '../../../models/seller_profile.dart';
import '../../../repositories/marketplace_repository.dart';
import 'seller_listing_filters.dart';
import 'seller_profile_state.dart';

/// Presentation logic for one public seller profile.
///
/// Scoped to the screen and disposed with it, like `ListingDetailController`:
/// two profiles must never share a "current seller". The controller makes no
/// request of its own; it forwards intent to the shared marketplace repository
/// that `MarketplaceScope` already provides, so no new scope or `main.dart`
/// wiring is needed.
///
/// ## Two independent surfaces
///
/// The header/profile payload and the Listings tab are separate requests. The
/// header loads on entry. The Listings tab loads lazily the first time it is
/// opened, like the Messages chips. A listings failure never replaces a profile
/// that loaded, and a profile failure never pretends the listings are gone.
///
/// ## Stale responses
///
/// Every first-page listings request takes a generation number. A response
/// whose generation is no longer current is discarded, so a pull-to-refresh
/// started while "load more" is in flight cannot append an older page on top
/// of newer results.
class SellerProfileController extends ChangeNotifier {
  SellerProfileController(this._repository, this.sellerId);

  final MarketplaceRepository _repository;

  /// `users.id` from the listing's seller projection.
  final int sellerId;

  /// How long typing must pause before the listing query is re-run.
  ///
  /// The marketplace's debounce, reused so search feels the same everywhere:
  /// one request per word, not one per keystroke.
  static const Duration searchDebounce = Duration(milliseconds: 350);

  SellerProfileState _state = const SellerProfileState();
  SellerProfileState get state => _state;

  bool _disposed = false;
  bool _profileInFlight = false;
  bool _loadingMore = false;
  int _listingsGeneration = 0;
  Timer? _searchDebounce;

  /// Loads the profile header once.
  ///
  /// Idempotent while a request is in flight, so `initState` plus a rebuild
  /// cannot cost two requests.
  Future<void> load() async {
    if (_profileInFlight) {
      return;
    }

    _profileInFlight = true;
    _set(
      _state.copyWith(
        status: SellerProfileStatus.loading,
        clearError: true,
        clearRefreshError: true,
      ),
    );

    try {
      final SellerProfile profile = await _repository.sellerProfile(sellerId);
      if (_disposed) {
        return;
      }
      _set(
        _state.copyWith(
          status: SellerProfileStatus.ready,
          profile: profile,
          clearError: true,
          clearRefreshError: true,
        ),
      );
    } on ApiException catch (error) {
      if (_disposed) {
        return;
      }
      _handleProfileFailure(error);
    } on Object {
      if (_disposed) {
        return;
      }
      _set(
        _state.copyWith(
          status: SellerProfileStatus.failed,
          errorMessage: 'Something went wrong. Please try again.',
        ),
      );
    } finally {
      _profileInFlight = false;
    }
  }

  /// Switches tabs, loading the Listings tab's first page on first open.
  Future<void> selectTab(SellerProfileTab tab) async {
    if (_state.selectedTab == tab) {
      return;
    }

    _set(_state.copyWith(selectedTab: tab));

    if (tab == SellerProfileTab.listings) {
      await ensureListings();
    }
  }

  /// Loads the Listings tab's first page unless it is already loaded or in
  /// flight.
  Future<void> ensureListings() async {
    switch (_state.listingsStatus) {
      case SellerListingsStatus.initial:
      case SellerListingsStatus.failed:
      case SellerListingsStatus.unavailable:
        await _loadListingsFirstPage();
        return;
      case SellerListingsStatus.loading:
      case SellerListingsStatus.loadingMore:
      case SellerListingsStatus.refreshing:
      case SellerListingsStatus.ready:
        return;
    }
  }

  /// Retries the Listings tab's first page after a failure.
  Future<void> retryListings() => _loadListingsFirstPage();

  /// Records new search text and schedules a debounced server query.
  ///
  /// No request is made per keystroke: the field updates immediately and the
  /// seller's whole visible inventory is re-queried once typing pauses. The
  /// filter is applied in SQL, so it is not limited to the loaded page.
  void updateSearch(String value) {
    if (_state.searchText == value) {
      return;
    }

    _set(_state.copyWith(searchText: value));
    _searchDebounce?.cancel();
    _searchDebounce = Timer(searchDebounce, () {
      _searchDebounce = null;
      unawaited(_loadListingsFirstPage());
    });
  }

  /// Applies the current search text immediately, skipping the debounce.
  Future<void> submitSearch() async {
    _searchDebounce?.cancel();
    _searchDebounce = null;
    await _loadListingsFirstPage();
  }

  /// Clears the search text and re-queries the full visible inventory.
  Future<void> clearSearch() async {
    if (_state.searchText.isEmpty) {
      return;
    }
    _set(_state.copyWith(searchText: ''));
    await submitSearch();
  }

  /// Selects an exact livestock category, or `null` for all categories.
  Future<void> selectCategory(String? value) async {
    final String next = (value ?? '').trim();
    if (_state.livestockType == next) {
      return;
    }
    _set(_state.copyWith(livestockType: next));
    await _loadListingsFirstPage();
  }

  /// Applies one documented server-side ordering.
  Future<void> selectSort(SellerListingSort sort) async {
    if (_state.sort == sort) {
      return;
    }
    _set(_state.copyWith(sort: sort));
    await _loadListingsFirstPage();
  }

  /// Clears search, category and ordering back to their defaults.
  Future<void> clearListingFilters() async {
    if (!_state.hasActiveListingFilters) {
      return;
    }

    _searchDebounce?.cancel();
    _searchDebounce = null;
    _set(
      _state.copyWith(
        searchText: '',
        livestockType: '',
        sort: SellerListingSort.newest,
      ),
    );
    await _loadListingsFirstPage();
  }

  /// Re-queries page 1 while keeping valid results on screen.
  ///
  /// Refreshes the profile header and, when the tab has been opened, the first
  /// listings page. A failed refresh leaves the current data in place and
  /// reports the failure separately; only a 404 — the seller is no longer
  /// public — replaces the screen with the unavailable state.
  Future<void> refresh() async {
    if (_state.status == SellerProfileStatus.loading ||
        _state.status == SellerProfileStatus.refreshing) {
      return;
    }

    if (_state.status != SellerProfileStatus.ready) {
      await load();
      return;
    }

    _set(
      _state.copyWith(
        status: SellerProfileStatus.refreshing,
        clearRefreshError: true,
      ),
    );

    try {
      final SellerProfile profile = await _repository.sellerProfile(sellerId);
      if (_disposed) {
        return;
      }
      _set(
        _state.copyWith(
          status: SellerProfileStatus.ready,
          profile: profile,
          clearRefreshError: true,
        ),
      );
    } on ApiException catch (error) {
      if (_disposed) {
        return;
      }
      if (error.kind == ApiErrorKind.notFound) {
        _set(
          _state.copyWith(
            status: SellerProfileStatus.unavailable,
            clearError: true,
          ),
        );
        return;
      }
      _set(
        _state.copyWith(
          status: SellerProfileStatus.ready,
          refreshErrorMessage: error.message,
        ),
      );
      return;
    } on Object {
      if (_disposed) {
        return;
      }
      _set(
        _state.copyWith(
          status: SellerProfileStatus.ready,
          refreshErrorMessage: 'Could not refresh the profile.',
        ),
      );
      return;
    }

    if (_state.listingsStatus == SellerListingsStatus.ready ||
        _state.listingsStatus == SellerListingsStatus.refreshing) {
      await _loadListingsFirstPage(keepResults: true);
    }
  }

  /// Appends the next listings page.
  Future<void> loadMoreListings() async {
    if (_loadingMore ||
        _state.listingsStatus != SellerListingsStatus.ready ||
        !_state.hasMoreListings) {
      return;
    }

    _loadingMore = true;
    final int generation = _listingsGeneration;

    _set(
      _state.copyWith(
        listingsStatus: SellerListingsStatus.loadingMore,
        clearListingsLoadMoreError: true,
      ),
    );

    try {
      final MarketplacePage page = await _repository.sellerListings(
        sellerId,
        page: (_state.pagination?.currentPage ?? 1) + 1,
        search: _state.searchText,
        livestockType: _state.livestockType,
        sort: _state.sort.value,
      );

      if (_disposed || generation != _listingsGeneration) {
        return;
      }

      _set(
        _state.copyWith(
          listingsStatus: SellerListingsStatus.ready,
          listings: <Listing>[..._state.listings, ...page.listings],
          pagination: page.pagination,
        ),
      );
    } on ApiException catch (error) {
      if (_disposed || generation != _listingsGeneration) {
        return;
      }
      _set(
        _state.copyWith(
          listingsStatus: SellerListingsStatus.ready,
          listingsLoadMoreErrorMessage: error.message,
        ),
      );
    } on Object {
      if (_disposed || generation != _listingsGeneration) {
        return;
      }
      _set(
        _state.copyWith(
          listingsStatus: SellerListingsStatus.ready,
          listingsLoadMoreErrorMessage:
              'Could not load more listings. Please try again.',
        ),
      );
    } finally {
      _loadingMore = false;
    }
  }

  void _handleProfileFailure(ApiException error) {
    if (error.kind == ApiErrorKind.notFound) {
      _set(
        _state.copyWith(
          status: SellerProfileStatus.unavailable,
          clearError: true,
        ),
      );
      return;
    }

    _set(
      _state.copyWith(
        status: SellerProfileStatus.failed,
        errorMessage: error.message,
      ),
    );
  }

  Future<void> _loadListingsFirstPage({bool keepResults = false}) async {
    _searchDebounce?.cancel();
    _searchDebounce = null;

    final int generation = ++_listingsGeneration;
    final bool keep = keepResults && _state.listings.isNotEmpty;

    _set(
      _state.copyWith(
        listingsStatus: keep
            ? SellerListingsStatus.refreshing
            : SellerListingsStatus.loading,
        clearListings: !keep,
        clearListingsError: true,
        clearListingsLoadMoreError: true,
        clearListingsRefreshError: true,
      ),
    );

    try {
      final MarketplacePage page = await _repository.sellerListings(
        sellerId,
        page: 1,
        search: _state.searchText,
        livestockType: _state.livestockType,
        sort: _state.sort.value,
      );

      if (_disposed || generation != _listingsGeneration) {
        return;
      }

      _set(
        _state.copyWith(
          listingsStatus: SellerListingsStatus.ready,
          listings: page.listings,
          pagination: page.pagination,
        ),
      );
    } on ApiException catch (error) {
      if (_disposed || generation != _listingsGeneration) {
        return;
      }

      if (error.kind == ApiErrorKind.notFound) {
        _set(
          _state.copyWith(
            listingsStatus: SellerListingsStatus.unavailable,
            clearListings: true,
            clearListingsError: true,
          ),
        );
        return;
      }

      if (keep) {
        _set(
          _state.copyWith(
            listingsStatus: SellerListingsStatus.ready,
            listingsRefreshErrorMessage: error.message,
          ),
        );
        return;
      }

      _set(
        _state.copyWith(
          listingsStatus: SellerListingsStatus.failed,
          listingsErrorMessage: error.message,
        ),
      );
    } on Object {
      if (_disposed || generation != _listingsGeneration) {
        return;
      }

      if (keep) {
        _set(
          _state.copyWith(
            listingsStatus: SellerListingsStatus.ready,
            listingsRefreshErrorMessage: 'Could not refresh the listings.',
          ),
        );
        return;
      }

      _set(
        _state.copyWith(
          listingsStatus: SellerListingsStatus.failed,
          listingsErrorMessage: 'Something went wrong. Please try again.',
        ),
      );
    }
  }

  void _set(SellerProfileState next) {
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
