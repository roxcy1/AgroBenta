import '../core/utils/json_utils.dart';
import 'listing.dart';
import 'pagination.dart';

/// One page of marketplace results: the listings plus their pagination.
///
/// Mirrors the `data` payload of `GET /api/listings`, which is the hand-rolled
/// paginated envelope from contract §3.2:
///
/// ```json
/// {
///   "success": true,
///   "data": {
///     "listings": [ /* MobileListingResource[] */ ],
///     "pagination": { "current_page": 1, "last_page": 5, "per_page": 15, "total": 68 }
///   }
/// }
/// ```
///
/// The array key is `listings` for this endpoint specifically. It is
/// endpoint-specific across the API (`users`, `transactions`, …) and must not be
/// generalised, which is why this is a named model rather than a generic
/// `PagedResponse<T>`.
///
/// ## Shared with the seller listing list
///
/// `GET /api/seller/listings` returns the same `{listings, pagination}` shape
/// with the same four pagination keys, so it is parsed by this same model rather
/// than a near-identical second one. Two models that must be kept in step because
/// the wire format must be kept in step is the wrong kind of duplication.
class MarketplacePage {
  const MarketplacePage({required this.listings, required this.pagination});

  factory MarketplacePage.fromJson(Map<String, dynamic> json) {
    return MarketplacePage(
      listings: readObjectList(
        json,
        'listings',
      ).map(Listing.fromJson).toList(growable: false),
      pagination: Pagination.fromJson(readObject(json, 'pagination')),
    );
  }

  /// The active listings on this page, newest first.
  ///
  /// Order is the server's: `created_at DESC, id DESC`. The app does not
  /// re-sort them, because doing so would disagree with the pagination the
  /// server computed over that same ordering.
  final List<Listing> listings;

  final Pagination pagination;

  /// Whether the server has another page after this one.
  bool get hasMore => pagination.hasNextPage;

  /// Whether this page carried no records.
  bool get isEmpty => listings.isEmpty;

  @override
  String toString() =>
      'MarketplacePage(${listings.length} listings, '
      'page ${pagination.currentPage}/${pagination.lastPage})';
}
