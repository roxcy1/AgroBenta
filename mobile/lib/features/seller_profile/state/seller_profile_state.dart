import '../../../models/listing.dart';
import '../../../models/pagination.dart';
import '../../../models/seller_profile.dart';
import 'seller_listing_filters.dart';

/// Lifecycle of the seller profile header.
enum SellerProfileStatus {
  /// Nothing requested yet.
  initial,

  /// First load in flight; the screen shows a blocking loader.
  loading,

  /// Profile loaded and displayable.
  ready,

  /// Profile reload in flight while the current profile stays on screen.
  refreshing,

  /// The seller is unknown, deleted, or has nothing public to show (404).
  unavailable,

  /// The request failed for another reason; retry is meaningful.
  failed,
}

/// Lifecycle of the Listings tab.
enum SellerListingsStatus {
  /// The tab has not been opened yet.
  initial,

  /// First page in flight, nothing to preserve.
  loading,

  /// At least one page is on screen.
  ready,

  /// A later page is being appended.
  loadingMore,

  /// Page 1 is being re-queried while results stay on screen.
  refreshing,

  /// The seller stopped being public while this tab was open (404).
  unavailable,

  /// The first page failed; retry is meaningful.
  failed,
}

/// The two tabs the design specifies. No third tab exists.
enum SellerProfileTab { profile, listings }

/// Immutable presentation state for one public seller profile.
class SellerProfileState {
  const SellerProfileState({
    this.status = SellerProfileStatus.initial,
    this.profile,
    this.errorMessage,
    this.refreshErrorMessage,
    this.selectedTab = SellerProfileTab.profile,
    this.searchText = '',
    this.livestockType = '',
    this.sort = SellerListingSort.newest,
    this.listingsStatus = SellerListingsStatus.initial,
    this.listings = const <Listing>[],
    this.pagination,
    this.listingsErrorMessage,
    this.listingsLoadMoreErrorMessage,
    this.listingsRefreshErrorMessage,
  });

  final SellerProfileStatus status;

  /// The public profile, once loaded. Kept during a refresh so the header does
  /// not blank while the request is in flight.
  final SellerProfile? profile;

  /// Displayable first-load failure message.
  final String? errorMessage;

  /// A failed refresh, shown above content that is still valid.
  final String? refreshErrorMessage;

  final SellerProfileTab selectedTab;

  /// The search text currently shown in the Listings filter field.
  final String searchText;

  /// Exact `listings.livestock_type` to filter by; empty means all categories.
  final String livestockType;

  /// The server-side ordering requested for the listing page.
  final SellerListingSort sort;

  final SellerListingsStatus listingsStatus;
  final List<Listing> listings;
  final Pagination? pagination;
  final String? listingsErrorMessage;
  final String? listingsLoadMoreErrorMessage;
  final String? listingsRefreshErrorMessage;

  /// Whether the header/content may be rendered.
  bool get isProfileReady =>
      status == SellerProfileStatus.ready ||
      status == SellerProfileStatus.refreshing;

  /// Whether the next page exists.
  bool get hasMoreListings => pagination?.hasNextPage ?? false;

  /// Whether any Listings filter is narrowing the server query.
  ///
  /// Newest is the default ordering, so it does not count as an active filter.
  bool get hasActiveListingFilters =>
      searchText.trim().isNotEmpty ||
      livestockType.trim().isNotEmpty ||
      sort != SellerListingSort.newest;

  /// Whether the first listings page has ever been attempted.
  bool get hasAttemptedListings =>
      listingsStatus != SellerListingsStatus.initial;

  SellerProfileState copyWith({
    SellerProfileStatus? status,
    SellerProfile? profile,
    String? errorMessage,
    String? refreshErrorMessage,
    SellerProfileTab? selectedTab,
    String? searchText,
    String? livestockType,
    SellerListingSort? sort,
    SellerListingsStatus? listingsStatus,
    List<Listing>? listings,
    Pagination? pagination,
    String? listingsErrorMessage,
    String? listingsLoadMoreErrorMessage,
    String? listingsRefreshErrorMessage,
    bool clearError = false,
    bool clearRefreshError = false,
    bool clearListings = false,
    bool clearListingsError = false,
    bool clearListingsLoadMoreError = false,
    bool clearListingsRefreshError = false,
  }) {
    return SellerProfileState(
      status: status ?? this.status,
      profile: profile ?? this.profile,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      refreshErrorMessage: clearRefreshError
          ? null
          : (refreshErrorMessage ?? this.refreshErrorMessage),
      selectedTab: selectedTab ?? this.selectedTab,
      searchText: searchText ?? this.searchText,
      livestockType: livestockType ?? this.livestockType,
      sort: sort ?? this.sort,
      listingsStatus: listingsStatus ?? this.listingsStatus,
      listings: clearListings ? const <Listing>[] : (listings ?? this.listings),
      pagination: pagination ?? this.pagination,
      listingsErrorMessage: clearListingsError
          ? null
          : (listingsErrorMessage ?? this.listingsErrorMessage),
      listingsLoadMoreErrorMessage: clearListingsLoadMoreError
          ? null
          : (listingsLoadMoreErrorMessage ?? this.listingsLoadMoreErrorMessage),
      listingsRefreshErrorMessage: clearListingsRefreshError
          ? null
          : (listingsRefreshErrorMessage ?? this.listingsRefreshErrorMessage),
    );
  }

  @override
  String toString() =>
      'SellerProfileState(${status.name}, tab: ${selectedTab.name}, '
      'listings: ${listingsStatus.name}, ${listings.length} loaded)';
}
