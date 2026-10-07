import '../core/constants/api_constants.dart';
import '../core/network/api_exception.dart';
import '../models/listing.dart';
import '../models/marketplace_page.dart';
import '../services/seller_listing_service.dart';

/// Orchestration for a seller's own listing management.
///
/// Thin, for the same reason `MarketplaceRepository` is: a read-only browse has
/// no session or lifetime concerns to arbitrate, and the write methods here are
/// single requests with no local state to reconcile. The one policy that
/// genuinely belongs at this layer is the page size — the server caps `per_page`
/// at 50 with a `422` for anything higher, and that is a fact about the API
/// rather than about any screen.
///
/// Error translation is deliberately **not** done here.
/// `ApiException.message` is already curated to be displayable, so a second layer
/// would be a second place for wording to drift.
class SellerListingRepository {
  const SellerListingRepository(this._service);

  final SellerListingService _service;

  /// Fetches one page of the caller's own listings.
  ///
  /// [perPage] is clamped to `1..[SellerListingEndpoints.maxPerPage]`. An
  /// out-of-range value is corrected silently rather than thrown: a page size is
  /// a presentation choice, and the caller cannot recover from it. Genuine
  /// problems — a `401`, a rejected filter — still propagate as [ApiException].
  Future<MarketplacePage> listMine({
    String? statusFilter,
    String? search,
    int page = 1,
    int? perPage,
  }) {
    return _service.listMine(
      statusFilter: statusFilter,
      search: search,
      // A page below 1 is meaningless to Laravel, which treats it as page 1.
      page: page < 1 ? 1 : page,
      perPage: _clampPerPage(perPage),
    );
  }

  /// Creates a draft owned by the caller.
  Future<Listing> create(Map<String, dynamic> fields) =>
      _service.create(fields);

  /// Edits a listing the caller owns.
  Future<Listing> update(int id, Map<String, dynamic> fields) =>
      _service.update(id, fields);

  /// Submits a draft for review.
  Future<Listing> submit(int id) => _service.submit(id);

  /// Destroys a draft or withdrawn listing.
  Future<void> delete(int id) => _service.delete(id);

  static int _clampPerPage(int? perPage) {
    final int requested = perPage ?? SellerListingEndpoints.defaultPerPage;
    if (requested < 1) {
      return 1;
    }
    if (requested > SellerListingEndpoints.maxPerPage) {
      return SellerListingEndpoints.maxPerPage;
    }
    return requested;
  }
}
