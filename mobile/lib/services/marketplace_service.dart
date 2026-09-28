import '../core/constants/api_constants.dart';
import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../models/listing.dart';
import '../models/marketplace_page.dart';

/// The buyer marketplace API surface.
///
/// Two methods, one per endpoint, and nothing else. No token handling, no
/// persistence, no error translation beyond what [ApiClient] already does —
/// those belong to `MarketplaceRepository`.
///
/// Both calls are `GET`, so this phase sends no request body at all and
/// therefore cannot send a server-owned field. `status`, `seller_id`, `role` and
/// `seller_capability` are not merely unused here, they are unreachable: the
/// only thing that leaves the device on this surface is the query map built in
/// [browse], and it is an explicit allow-list (functional documentation §10.1,
/// §10.2).
class MarketplaceService {
  const MarketplaceService(this._apiClient);

  final ApiClient _apiClient;

  /// `GET /listings` — one page of active listings.
  ///
  /// [search] is matched server-side against `livestock_type`, `breed` and
  /// `location`, so it narrows the whole result set rather than the page
  /// already loaded. [livestockType] and [location] are exact-match filters on
  /// free-text columns. [minPrice] and [maxPrice] bound `asking_price`.
  ///
  /// Every parameter is optional and blank strings are treated as absent, so
  /// the default request is a bare `GET /listings` rather than a request
  /// carrying empty filters.
  ///
  /// Throws [ApiException]:
  ///  * `unauthorized` on a `401` — the token was missing or revoked, and
  ///    `ApiClient` has already cleared it. The app is signed out; the screen
  ///    surfaces this through the gate rather than as a list error.
  ///  * `validation` on a `422`, carrying per-field messages. A filter the
  ///    server rejected is a client bug, not a user error to bury.
  ///  * `notFound` is **not** expected here — a hidden listing is filtered out
  ///    of the result set, so it never appears and never 404s the list.
  Future<MarketplacePage> browse({
    String? search,
    String? livestockType,
    String? location,
    String? minPrice,
    String? maxPrice,
    int page = 1,
    int perPage = MarketplaceEndpoints.defaultPerPage,
  }) {
    return _apiClient.get<MarketplacePage>(
      MarketplaceEndpoints.browse,
      query: <String, dynamic>{
        // Explicit allow-list. Anything not named here has no path to the
        // request, so a field added to the model can never become a filter.
        if (_present(search)) 'search': search!.trim(),
        if (_present(livestockType)) 'livestock_type': livestockType!.trim(),
        if (_present(location)) 'location': location!.trim(),
        if (_present(minPrice)) 'min_price': minPrice!.trim(),
        if (_present(maxPrice)) 'max_price': maxPrice!.trim(),
        'page': page,
        'per_page': perPage,
      },
      parse: (Object? data) => MarketplacePage.fromJson(
        _asObject(data, 'GET /listings'),
      ),
    );
  }

  /// `GET /listings/{listing}` — one listing's detail.
  ///
  /// The detail endpoint is the source of truth for a listing, not the object
  /// the list happened to return: a listing can leave the marketplace between
  /// the two requests, and this call is what finds out.
  ///
  /// A `404` is a normal outcome, not an error to swallow: the listing was
  /// `draft`, `pending`, `inactive` or `sold` (or never existed), and by [D-02]
  /// the server answers `404` rather than `403` for all of those so listing
  /// existence is not disclosed. It surfaces as
  /// [ApiErrorKind.notFound] and the screen renders "no longer available".
  Future<Listing> detail(int id) {
    return _apiClient.get<Listing>(
      MarketplaceEndpoints.detail(id),
      parse: (Object? data) => Listing.fromJson(_asObject(data, 'GET /listings/$id')),
    );
  }

  static bool _present(String? value) => value != null && value.trim().isNotEmpty;

  /// Casts an unwrapped `data` payload to a JSON object with a message that
  /// names the endpoint, instead of a bare cast error. A `FormatException` here
  /// is translated by `ApiClient` into [ApiErrorKind.malformedResponse].
  static Map<String, dynamic> _asObject(Object? data, String context) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return data.cast<String, dynamic>();
    }
    throw FormatException(
      'Expected the $context response data to be a JSON object, got '
      '${data.runtimeType}.',
    );
  }
}
