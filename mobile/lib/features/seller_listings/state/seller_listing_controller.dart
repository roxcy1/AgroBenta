import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../models/listing.dart';
import '../../../models/marketplace_page.dart';
import '../../../repositories/seller_listing_repository.dart';
import 'seller_listing_draft.dart';
import 'seller_listing_state.dart';

/// Presentation logic for a seller's own listings.
///
/// The only thing that mutates [state]. The screens call these methods and
/// listen; they never touch the repository or `ApiClient`.
///
/// ## The rule this class exists to enforce
///
/// **A seller moves a listing forward, never sideways or back.** Creation makes
/// a `draft`. Submission makes it `pending`. There is no method that sets
/// `active`, `sold` or `inactive`, and no path by which calling one of these
/// could send such a value: the repository's bodies are filtered by
/// [SellerListingService.writableBody], which contains no status field. The
/// client's idea of the lifecycle is a strict subset of the server's, which is
/// what stops the two from disagreeing about what a seller is allowed to do.
///
/// Availability is decided by the **server's** rules and mirrored in
/// [SellerListingState] so the UI never offers an action that would answer `409`:
/// a `draft` can be edited, submitted and deleted; an `active` listing can be
/// edited but not deleted; `pending` can do neither; an `inactive` listing can
/// only be deleted. The mirror is a convenience, never the enforcement — every
/// transition below is checked again server-side.
///
/// ## Errors
///
/// Each [ApiErrorKind] is handled for what it *is*:
///
///  * `409` — the listing is not in a state for that action. Not a fault and not
///    a validation problem; it lands in [SellerListingState.conflictMessage] and
///    the list is re-read so the screen settles on the real state.
///  * `422` — per-field messages, shown beside the fields.
///  * `403` — the account is not an approved seller. Reported as an error rather
///    than as an empty list, because an empty list would imply "you have no
///    listings" when the truth is "you may not ask".
class SellerListingController extends ChangeNotifier {
  SellerListingController(this._repository);

  /// How long typing must pause before the list is re-queried.
  static const Duration searchDebounce = Duration(milliseconds: 350);

  final SellerListingRepository _repository;

  SellerListingState _state = const SellerListingState();
  SellerListingState get state => _state;

  Timer? _searchDebounce;
  bool _disposed = false;

  /// Incremented for every first-page request; a stale response is discarded.
  int _generation = 0;

  /// Guards against a second page request while one is in flight.
  bool _loadingMore = false;

  /// The query of the first-page request currently in flight, or `null`.
  ///
  /// Lets [loadInitial] be idempotent without blocking the calls that *should*
  /// interrupt it: a rebuild that re-enters it must not cost a second request,
  /// while a changed filter genuinely has to supersede whatever is in flight.
  String? _inFlightFirstPageQuery;

  /// Loads the first page, unless that exact query is already being fetched.
  Future<void> loadInitial() {
    final String query = _firstPageQuery;
    if (_inFlightFirstPageQuery == query) {
      return Future<void>.value();
    }
    return _loadFirstPage();
  }

  /// Re-queries the first page, keeping the current filter and search.
  ///
  /// The error state's retry: there is nothing on screen to preserve, so a
  /// failure produces the full-screen error again.
  Future<void> retry() => _loadFirstPage();

  /// Pull-to-refresh: re-queries page 1 **without** clearing the list.
  Future<void> refresh() async {
    if (_state.status == SellerListingStatus.loading ||
        _state.status == SellerListingStatus.refreshing) {
      return;
    }

    if (_state.status == SellerListingStatus.initial ||
        _state.status == SellerListingStatus.failed ||
        _state.listings.isEmpty) {
      await retry();
      return;
    }

    await _loadFirstPage(keepResults: true);
  }

  /// Records new search text and schedules a debounced request.
  void updateSearch(String value) {
    if (_state.searchText == value) {
      return;
    }
    _set(_state.copyWith(searchText: value));
    _scheduleSearch();
  }

  /// Applies the search text immediately, cancelling any pending debounce.
  Future<void> submitSearch() async {
    _searchDebounce?.cancel();
    _searchDebounce = null;
    await _loadFirstPage();
  }

  /// Applies a status filter and reloads from page 1.
  ///
  /// Pagination is always reset: keeping page 3 of one result set while showing a
  /// filter for a different query would be meaningless. Re-applying an identical
  /// filter is a no-op rather than a request.
  Future<void> applyStatusFilter(ListingStatus? status) async {
    if (status == _state.statusFilter) {
      return;
    }
    _set(
      status == null
          ? _state.copyWith(clearStatusFilter: true)
          : _state.copyWith(statusFilter: status),
    );
    await _loadFirstPage();
  }

  /// Clears the filter and the search in a single request.
  Future<void> clearQuery() async {
    if (!_state.hasActiveQuery) {
      return;
    }
    _searchDebounce?.cancel();
    _searchDebounce = null;
    _set(_state.copyWith(clearStatusFilter: true, searchText: ''));
    await _loadFirstPage();
  }

  /// Loads the next page and appends it to what is already on screen.
  ///
  /// Does nothing when a page is loading, when the first page has not succeeded,
  /// or when the server has reported no further pages.
  Future<void> loadMore() async {
    if (_loadingMore ||
        _state.isBusy ||
        _state.listings.isEmpty ||
        !_state.hasMorePages) {
      return;
    }

    _loadingMore = true;
    final int generation = _generation;
    _set(
      _state.copyWith(
        status: SellerListingStatus.loadingMore,
        clearLoadMoreError: true,
      ),
    );

    try {
      final MarketplacePage page = await _repository.listMine(
        statusFilter: _state.statusFilter?.value,
        search: _state.searchText,
        page: _state.currentPage + 1,
      );

      if (_disposed || generation != _generation) {
        return;
      }

      _set(
        _state.copyWith(
          status: SellerListingStatus.ready,
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
          status: SellerListingStatus.ready,
          loadMoreErrorMessage: error.message,
        ),
      );
    } on Object {
      if (_disposed || generation != _generation) {
        return;
      }
      _set(
        _state.copyWith(
          status: SellerListingStatus.ready,
          loadMoreErrorMessage:
              'Could not load more listings. Please try again.',
        ),
      );
    } finally {
      _loadingMore = false;
    }
  }

  /// Creates a draft from [draft]. Returns the created listing, or `null`.
  ///
  /// A second call while a creation is in flight returns `null` without touching
  /// the network. That is the duplicate-submission guard, and it lives here
  /// rather than only as a disabled button: a disabled button stops a tap, but
  /// not the request already in flight from being followed by another, and the
  /// seller would end up with two identical drafts.
  ///
  /// On success the created listing is put at the head of the list rather than
  /// triggering a reload, because the server returned the whole record. The list
  /// is *also* re-read in the background so the ordering and the pagination total
  /// come from the server rather than from this guess.
  Future<Listing?> create(SellerListingDraft draft) async {
    if (_state.isActioning) {
      return null;
    }

    _beginAction(SellerListingAction.creating, clearActionListingId: true);

    try {
      final Listing created = await _repository.create(draft.toRequestBody());

      if (_disposed) {
        return null;
      }

      _endAction(message: 'Listing saved as a draft.');
      _set(
        _state.copyWith(
          listings: <Listing>[
            created,
            ..._state.listings.where((Listing l) => l.id != created.id),
          ],
        ),
      );
      unawaited(refresh());
      return created;
    } on ApiException catch (error) {
      if (_disposed) {
        return null;
      }
      _failAction(error);
      return null;
    } on Object {
      if (_disposed) {
        return null;
      }
      _set(
        _state.copyWith(
          action: SellerListingAction.none,
          clearActionListingId: true,
          actionErrorMessage: 'Something went wrong. Please try again.',
        ),
      );
      return null;
    }
  }

  /// Edits [listingId] from [draft]. Returns the updated listing, or `null`.
  ///
  /// The draft is sent whole, which is valid on a PATCH: every field the form
  /// owns is present, and fields the seller left empty are omitted rather than
  /// sent as null, so nothing they did not touch is cleared.
  Future<Listing?> update(int listingId, SellerListingDraft draft) async {
    if (_state.isActioning) {
      return null;
    }

    _beginAction(SellerListingAction.updating, listingId: listingId);

    try {
      final Listing updated = await _repository.update(
        listingId,
        draft.toRequestBody(),
      );

      if (_disposed) {
        return null;
      }

      _endAction(message: 'Listing updated.');
      _replaceListing(updated);
      return updated;
    } on ApiException catch (error) {
      if (_disposed) {
        return null;
      }
      _failAction(error);
      return null;
    } on Object {
      if (_disposed) {
        return null;
      }
      _set(
        _state.copyWith(
          action: SellerListingAction.none,
          clearActionListingId: true,
          actionErrorMessage: 'Something went wrong. Please try again.',
        ),
      );
      return null;
    }
  }

  /// Submits [listingId] for review. Returns the updated listing, or `null`.
  ///
  /// The one transition a seller can make, and one-way: the server answers `409`
  /// for anything that is not a draft, which lands in
  /// [SellerListingState.conflictMessage] with the list re-read behind it.
  Future<Listing?> submit(int listingId) async {
    if (_state.isActioning) {
      return null;
    }

    _beginAction(SellerListingAction.submitting, listingId: listingId);

    try {
      final Listing submitted = await _repository.submit(listingId);

      if (_disposed) {
        return null;
      }

      _endAction(message: 'Listing submitted for review.');
      _replaceListing(submitted);
      return submitted;
    } on ApiException catch (error) {
      if (_disposed) {
        return null;
      }
      _failAction(error, reloadAfterConflict: true);
      return null;
    } on Object {
      if (_disposed) {
        return null;
      }
      _set(
        _state.copyWith(
          action: SellerListingAction.none,
          clearActionListingId: true,
          actionErrorMessage: 'Something went wrong. Please try again.',
        ),
      );
      return null;
    }
  }

  /// Destroys [listingId]. Returns `true` when the server confirmed it.
  ///
  /// A draft or withdrawn listing only. This is a deletion and **not** a
  /// deactivation: taking a live listing out of sale is an administrator's
  /// decision, and no seller route exists for it.
  ///
  /// The row is removed from the list on success rather than by reloading, so the
  /// list does not jump. A delete genuinely changes the `total` and the page
  /// count, so a refresh follows in the background to correct them.
  Future<bool> delete(int listingId) async {
    if (_state.isActioning) {
      return false;
    }

    _beginAction(SellerListingAction.deleting, listingId: listingId);

    try {
      await _repository.delete(listingId);

      if (_disposed) {
        return false;
      }

      _endAction(message: 'Listing deleted.');
      _set(
        _state.copyWith(
          listings: _state.listings
              .where((Listing listing) => listing.id != listingId)
              .toList(growable: false),
        ),
      );
      unawaited(refresh());
      return true;
    } on ApiException catch (error) {
      if (_disposed) {
        return false;
      }
      _failAction(error, reloadAfterConflict: true);
      return false;
    } on Object {
      if (_disposed) {
        return false;
      }
      _set(
        _state.copyWith(
          action: SellerListingAction.none,
          clearActionListingId: true,
          actionErrorMessage: 'Something went wrong. Please try again.',
        ),
      );
      return false;
    }
  }

  /// Discards a form-level message so a retry starts clean.
  void clearActionMessage() {
    if (_state.actionErrorMessage == null &&
        _state.conflictMessage == null &&
        _state.actionMessage == null &&
        _state.validationErrors.isEmpty) {
      return;
    }
    _set(
      _state.copyWith(
        clearActionError: true,
        clearConflict: true,
        clearActionMessage: true,
        validationErrors: const <String, List<String>>{},
      ),
    );
  }

  /// Whether a listing can be edited right now.
  ///
  /// Mirrors the server rule ([D-24]: `draft` and `active`), so the Edit action
  /// is not offered for a listing that would answer `409`. A `pending` listing is
  /// with an administrator; changing it mid-review is not the seller's call.
  static bool canEdit(Listing listing) =>
      listing.status == ListingStatus.draft ||
      listing.status == ListingStatus.active;

  /// Whether a listing can be submitted for review right now.
  ///
  /// Only a `draft`. There is no reverse transition, so a listing that has been
  /// submitted cannot be recalled by the seller.
  static bool canSubmit(Listing listing) =>
      listing.status == ListingStatus.draft;

  /// Whether a listing can be deleted right now.
  ///
  /// A `draft` or a withdrawn `inactive` listing ([D-25]). Not a `pending`
  /// listing, which is in an administrator's queue, and emphatically not an
  /// `active` one.
  static bool canDelete(Listing listing) =>
      listing.status == ListingStatus.draft ||
      listing.status == ListingStatus.inactive;

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
  String get _firstPageQuery =>
      '${_state.statusFilter?.value ?? ''}|${_state.searchText}|1';

  Future<void> _loadFirstPage({bool keepResults = false}) async {
    _searchDebounce?.cancel();
    _searchDebounce = null;

    final int generation = ++_generation;
    final String query = _firstPageQuery;
    _inFlightFirstPageQuery = query;

    _set(
      _state.copyWith(
        status: keepResults
            ? SellerListingStatus.refreshing
            : SellerListingStatus.loading,
        clearListings: !keepResults,
        clearError: true,
        clearLoadMoreError: true,
        clearRefreshError: true,
      ),
    );

    try {
      final MarketplacePage page = await _repository.listMine(
        statusFilter: _state.statusFilter?.value,
        search: _state.searchText,
        page: 1,
      );

      if (_disposed || generation != _generation) {
        return;
      }

      _inFlightFirstPageQuery = null;
      _set(
        _state.copyWith(
          status: SellerListingStatus.ready,
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
                status: SellerListingStatus.ready,
                refreshErrorMessage: error.message,
              )
            : _state.copyWith(
                status: SellerListingStatus.failed,
                errorMessage: error.message,
              ),
      );
    } on Object {
      if (_disposed || generation != _generation) {
        return;
      }
      _inFlightFirstPageQuery = null;
      _set(
        keepResults
            ? _state.copyWith(
                status: SellerListingStatus.ready,
                refreshErrorMessage: 'Something went wrong. Please try again.',
              )
            : _state.copyWith(
                status: SellerListingStatus.failed,
                errorMessage: 'Something went wrong. Please try again.',
              ),
      );
    }
  }

  /// Swaps one listing in place, keeping the list's order and length.
  void _replaceListing(Listing updated) {
    _set(
      _state.copyWith(
        listings: _state.listings
            .map(
              (Listing listing) => listing.id == updated.id ? updated : listing,
            )
            .toList(growable: false),
      ),
    );
  }

  void _beginAction(
    SellerListingAction action, {
    int? listingId,
    bool clearActionListingId = false,
  }) {
    _set(
      _state.copyWith(
        action: action,
        actionListingId: listingId,
        clearActionListingId: clearActionListingId || listingId == null,
        clearActionError: true,
        clearConflict: true,
        clearActionMessage: true,
        validationErrors: const <String, List<String>>{},
      ),
    );
  }

  void _endAction({required String message}) {
    _set(
      _state.copyWith(
        action: SellerListingAction.none,
        clearActionListingId: true,
        actionMessage: message,
      ),
    );
  }

  /// Routes an [ApiException] to the right slot for what it *is*.
  ///
  /// [reloadAfterConflict] is set for actions where a `409` means the server's
  /// view has moved on from the screen's — a listing already submitted, or one
  /// that has since been approved. The list is re-read so the row settles on the
  /// truth rather than on a status the client still believes.
  void _failAction(ApiException error, {bool reloadAfterConflict = false}) {
    if (error.kind == ApiErrorKind.conflict) {
      _set(
        _state.copyWith(
          action: SellerListingAction.none,
          clearActionListingId: true,
          conflictMessage: error.message,
        ),
      );
      if (reloadAfterConflict) {
        unawaited(refresh());
      }
      return;
    }

    if (error.kind == ApiErrorKind.validation) {
      _set(
        _state.copyWith(
          action: SellerListingAction.none,
          clearActionListingId: true,
          actionErrorMessage: error.message,
          validationErrors: error.validationErrors,
        ),
      );
      return;
    }

    _set(
      _state.copyWith(
        action: SellerListingAction.none,
        clearActionListingId: true,
        actionErrorMessage: error.message,
      ),
    );
  }

  void _set(SellerListingState next) {
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
