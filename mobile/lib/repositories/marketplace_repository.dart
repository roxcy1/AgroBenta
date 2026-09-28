import '../core/constants/api_constants.dart';
import '../core/network/api_exception.dart';
import '../models/listing.dart';
import '../models/marketplace_page.dart';
import '../services/marketplace_service.dart';

/// Orchestration for the buyer marketplace.
///
/// Thin by design, because a read-only browse has no session or lifetime
/// concerns to arbitrate the way `AuthRepository` does. The one policy that
/// genuinely belongs here is the page size: the server caps `per_page` at 50
/// with a `422` for anything higher, and that limit is a fact about the API
/// rather than about any screen. Clamping it here means no widget can discover
/// the cap by provoking an error, and the constant lives beside the endpoint it
/// belongs to.
///
/// Error translation is deliberately **not** done here. `ApiException.message`
/// is already curated to be displayable, so a second translation layer would be
/// a second place for wording to drift.
class MarketplaceRepository {
  const MarketplaceRepository(this._service);

  final MarketplaceService _service;

  /// Fetches one page of active listings.
  ///
  /// [perPage] is clamped to `1..[MarketplaceEndpoints.maxPerPage]`. An
  /// out-of-range value is corrected silently rather than thrown: a page size
  /// is a presentation choice, and the caller is not in a position to recover
  /// from it. Genuine problems with the request — an unauthenticated session, a
  /// rejected filter — still propagate as [ApiException].
  Future<MarketplacePage> browse({
    String? search,
    String? livestockType,
    String? minPrice,
    String? maxPrice,
    int page = 1,
    int? perPage,
  }) {
    return _service.browse(
      search: search,
      livestockType: livestockType,
      minPrice: minPrice,
      maxPrice: maxPrice,
      // A page below 1 is meaningless to Laravel, which treats it as page 1.
      page: page < 1 ? 1 : page,
      perPage: _clampPerPage(perPage),
    );
  }

  /// Fetches one listing's detail.
  ///
  /// Throws [ApiException] with [ApiErrorKind.notFound] when the listing is not
  /// visible to the caller.
  Future<Listing> detail(int id) => _service.detail(id);

  static int _clampPerPage(int? perPage) {
    final int requested = perPage ?? MarketplaceEndpoints.defaultPerPage;
    if (requested < 1) {
      return 1;
    }
    if (requested > MarketplaceEndpoints.maxPerPage) {
      return MarketplaceEndpoints.maxPerPage;
    }
    return requested;
  }
}
