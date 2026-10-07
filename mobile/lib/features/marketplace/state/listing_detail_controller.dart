import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../models/listing.dart';
import '../../../repositories/marketplace_repository.dart';
import 'listing_detail_state.dart';

/// Presentation logic for one listing's detail screen.
///
/// Scoped to a single listing rather than shared through a scope, because its
/// state is per-listing: two detail screens for different listings must not
/// share a "current" listing, and a global controller holding a nullable
/// `currentListingId` would be a race waiting to happen. The screen owns an
/// instance and disposes it.
///
/// [load] is idempotent and re-entrant-safe: a second call while one is in
/// flight does not start a second request, and a response that arrives after
/// [dispose] is dropped rather than notifying a dead listener.
class ListingDetailController extends ChangeNotifier {
  ListingDetailController(this._repository, this.listingId);

  final MarketplaceRepository _repository;
  final int listingId;

  ListingDetailState _state = const ListingDetailState();
  ListingDetailState get state => _state;

  bool _disposed = false;
  bool _inFlight = false;

  /// Fetches the listing from `GET /listings/{listing}`.
  ///
  /// This is the source of truth for what the screen shows. Nothing is taken
  /// from the list response: passing a whole listing object down would display
  /// data the detail endpoint has not confirmed is still visible, which is
  /// precisely the case the `404` handling exists for.
  Future<void> load() async {
    if (_inFlight) {
      return;
    }

    _inFlight = true;
    _set(const ListingDetailState(status: ListingDetailStatus.loading));

    try {
      final Listing listing = await _repository.detail(listingId);
      if (_disposed) {
        return;
      }
      _set(
        ListingDetailState(status: ListingDetailStatus.ready, listing: listing),
      );
    } on ApiException catch (error) {
      if (_disposed) {
        return;
      }

      if (error.kind == ApiErrorKind.notFound) {
        // Not an error to apologise for. The listing left the marketplace or
        // was never visible to this buyer, and the server will not say which.
        _set(const ListingDetailState(status: ListingDetailStatus.unavailable));
        return;
      }

      _set(
        ListingDetailState(
          status: ListingDetailStatus.failed,
          errorMessage: error.message,
        ),
      );
    } on Object {
      if (_disposed) {
        return;
      }
      _set(
        const ListingDetailState(
          status: ListingDetailStatus.failed,
          errorMessage: 'Something went wrong. Please try again.',
        ),
      );
    } finally {
      _inFlight = false;
    }
  }

  void _set(ListingDetailState next) {
    if (_disposed) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
