import '../../../models/listing.dart';
import '../../../models/pagination.dart';

/// Where the seller listing list is in its lifecycle.
///
/// Mirrors `MarketplaceStatus` for the same reason it does: these are mutually
/// exclusive presentations, and modelling them as booleans is how a list ends up
/// showing a spinner and an error at once.
///
/// Split rather than shared with the marketplace because the seller list is not
/// the same screen. It is not read-only, its empty state is actionable, and its
/// rows carry management actions — a buyer list and a seller list that happen to
/// share a base class would be one `copyWith` away from a wrong answer.
enum SellerListingStatus {
  /// Constructed but nothing requested yet.
  initial,

  /// The first page is in flight and there is nothing to show yet.
  loading,

  /// At least one page is loaded. The screen may still be fetching another.
  ready,

  /// A page after the first is in flight, and the results already on screen stay.
  loadingMore,

  /// Page 1 is being re-queried while results are already on screen.
  ///
  /// Pull-to-refresh must not blank a list the user is reading, so this keeps the
  /// existing rows and swaps them when the response lands. A failure returns to
  /// [ready] with a notice rather than replacing the screen with an error.
  refreshing,

  /// The first page failed. There is nothing on screen to preserve.
  failed,
}

/// Which management action, if any, is in flight.
///
/// One enum rather than a boolean per action, so "submitting and deleting at
/// once" is not a representable state. A second tap on a row while its own action
/// is running is refused by the controller, and this is what the UI reads to
/// decide which row's button shows a spinner.
enum SellerListingAction {
  /// Nothing in flight.
  none,

  /// `POST /seller/listings`.
  creating,

  /// `PATCH /seller/listings/{id}`.
  updating,

  /// `POST /seller/listings/{id}/submit`.
  submitting,

  /// `DELETE /seller/listings/{id}`.
  deleting,
}

/// An immutable snapshot of everything the seller listing screens render from.
///
/// The screen reads this and nothing else. It never asks the repository directly
/// and never infers a state the controller did not publish.
class SellerListingState {
  const SellerListingState({
    this.status = SellerListingStatus.initial,
    this.listings = const <Listing>[],
    this.pagination,
    this.statusFilter,
    this.searchText = '',
    this.errorMessage,
    this.loadMoreErrorMessage,
    this.refreshErrorMessage,
    this.action = SellerListingAction.none,
    this.actionListingId,
    this.actionMessage,
    this.actionErrorMessage,
    this.conflictMessage,
    this.validationErrors = const <String, List<String>>{},
  });

  final SellerListingStatus status;

  /// Every listing loaded so far, in server order. Accumulates across pages.
  final List<Listing> listings;

  /// Pagination for the most recent page received, or `null` before the first
  /// successful response.
  final Pagination? pagination;

  /// The status the list is currently narrowed to, or `null` for all of them.
  ///
  /// `null` is the default and is not the same as "no listings": it means the
  /// seller is seeing their own work in every state, which is the point of the
  /// screen.
  final ListingStatus? statusFilter;

  /// What the search field shows, which is not always what has been searched
  /// for: the user may be mid-type while the last debounce is still pending.
  final String searchText;

  /// A displayable failure for the whole screen.
  final String? errorMessage;

  /// A displayable failure for a *subsequent* page.
  ///
  /// Separate from [errorMessage] on purpose: the listings already loaded are
  /// still valid, so a page-3 failure must not discard them or cover them with a
  /// full-screen error.
  final String? loadMoreErrorMessage;

  /// A displayable failure for a re-query of the first page that kept the
  /// existing listings.
  final String? refreshErrorMessage;

  /// The management action in flight, or [SellerListingAction.none].
  final SellerListingAction action;

  /// The id of the listing an in-flight action is for, or `null` for [create].
  ///
  /// Paired with [action] so a busy spinner lands on the row that is busy rather
  /// than on every row in the list.
  final int? actionListingId;

  /// A confirmation of the last successful action, for a snackbar.
  ///
  /// The success the design system asks for on a significant action like
  /// "Listing submitted" — though it is never the *only* record: the list behind
  /// it is re-read so the change is visible there too.
  final String? actionMessage;

  /// A displayable failure for a management action.
  final String? actionErrorMessage;

  /// Set when an action was refused with a `409`.
  ///
  /// Kept apart from [actionErrorMessage] because a `409` is not a fault. The
  /// seller did nothing wrong: the listing is simply not in a state where that
  /// action exists, and showing it in the same red banner as a network failure
  /// would tell them something is broken when the only true thing is that the
  /// listing has already moved on.
  final String? conflictMessage;

  /// Per-field messages from a `422`, keyed by contract field name. Rendered
  /// beside the field rather than as a dump.
  final Map<String, List<String>> validationErrors;

  /// 1-based page currently displayed, or 0 before anything has loaded.
  int get currentPage => pagination?.currentPage ?? 0;

  /// Whether the server has another page.
  bool get hasMorePages => pagination?.hasNextPage ?? false;

  /// Loaded, but with no listings. The screen distinguishes this from
  /// [SellerListingStatus.failed] and from a first load still in progress.
  bool get isEmpty => status == SellerListingStatus.ready && listings.isEmpty;

  /// Whether the list is narrowed by a search or a status filter. Drives the
  /// empty state's wording: "You have not created a listing yet" and "No
  /// listings match" are different facts about the world.
  bool get hasActiveQuery =>
      searchText.trim().isNotEmpty || statusFilter != null;

  /// A read request is in flight.
  bool get isBusy =>
      status == SellerListingStatus.loading ||
      status == SellerListingStatus.loadingMore ||
      status == SellerListingStatus.refreshing;

  /// A management action is in flight.
  bool get isActioning => action != SellerListingAction.none;

  /// The whole list is replaced by a loading or error state.
  bool get showsBlockingState =>
      status == SellerListingStatus.loading ||
      status == SellerListingStatus.failed;

  /// The listings in the list that match [status], in server order.
  ///
  /// Only meaningful when [statusFilter] is `null`, in which case the server has
  /// already narrowed the result set and this is the identity — which is why it
  /// is not used to filter. A client-side filter would disagree with the
  /// pagination the server computed.
  List<Listing> listingsWithStatus(ListingStatus status) => listings
      .where((Listing listing) => listing.status == status)
      .toList(growable: false);

  /// Counts per status across the loaded listings.
  ///
  /// For the filter chips' labels. Derived from what is loaded, so it is a count
  /// of the current page set rather than of the whole seller's inventory — the
  /// chips are a navigation aid, not a report, and labelling them with a count
  /// that contradicts the server's `total` would be worse than no count.
  Map<ListingStatus, int> get countsByStatus {
    final Map<ListingStatus, int> counts = <ListingStatus, int>{
      for (final ListingStatus status in ListingStatus.values) status: 0,
    };
    for (final Listing listing in listings) {
      counts[listing.status] = (counts[listing.status] ?? 0) + 1;
    }
    return counts;
  }

  /// Whether a management action on [listingId] is the one in flight.
  bool isActingOn(int listingId) => actionListingId == listingId && isActioning;

  /// The validation message for one field, or `null`.
  ///
  /// Takes the first message: Laravel sends one per rule, and stacking several
  /// under a single-line field is noise.
  String? errorFor(String field) {
    final List<String>? messages = validationErrors[field];
    if (messages == null || messages.isEmpty) {
      return null;
    }
    return messages.first;
  }

  /// Finds a loaded listing by id, or `null`.
  ///
  /// The detail screen reads the current copy from the list so a mutation
  /// updates the open screen as well as the row behind it, instead of leaving a
  /// stale status on display.
  Listing? findListing(int id) {
    for (final Listing listing in listings) {
      if (listing.id == id) {
        return listing;
      }
    }
    return null;
  }

  SellerListingState copyWith({
    SellerListingStatus? status,
    List<Listing>? listings,
    Pagination? pagination,
    ListingStatus? statusFilter,
    bool clearStatusFilter = false,
    String? searchText,
    String? errorMessage,
    String? loadMoreErrorMessage,
    String? refreshErrorMessage,
    SellerListingAction? action,
    int? actionListingId,
    bool clearActionListingId = false,
    String? actionMessage,
    String? actionErrorMessage,
    String? conflictMessage,
    Map<String, List<String>>? validationErrors,
    bool clearError = false,
    bool clearLoadMoreError = false,
    bool clearRefreshError = false,
    bool clearActionMessage = false,
    bool clearActionError = false,
    bool clearConflict = false,
    bool clearListings = false,
  }) {
    return SellerListingState(
      status: status ?? this.status,
      listings: clearListings ? const <Listing>[] : (listings ?? this.listings),
      pagination: pagination ?? this.pagination,
      statusFilter: clearStatusFilter
          ? null
          : (statusFilter ?? this.statusFilter),
      searchText: searchText ?? this.searchText,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      loadMoreErrorMessage: clearLoadMoreError
          ? null
          : (loadMoreErrorMessage ?? this.loadMoreErrorMessage),
      refreshErrorMessage: clearRefreshError
          ? null
          : (refreshErrorMessage ?? this.refreshErrorMessage),
      action: action ?? this.action,
      actionListingId: clearActionListingId
          ? null
          : (actionListingId ?? this.actionListingId),
      actionMessage: clearActionMessage
          ? null
          : (actionMessage ?? this.actionMessage),
      actionErrorMessage: clearActionError
          ? null
          : (actionErrorMessage ?? this.actionErrorMessage),
      conflictMessage: clearConflict
          ? null
          : (conflictMessage ?? this.conflictMessage),
      validationErrors: validationErrors ?? this.validationErrors,
    );
  }

  @override
  String toString() =>
      'SellerListingState(${status.name}, ${listings.length} listings, '
      'page $currentPage, filter: ${statusFilter?.name ?? 'all'})';
}
