/// Transport-level constants for API communication.
///
/// Endpoint paths live here, one group per feature, and only once the backend
/// actually serves them. M0 deliberately carried no paths at all: the backend
/// exposed nothing mobile-facing then, and writing a path for an endpoint that
/// does not exist is how invented contracts start. The mobile authentication
/// routes are implemented (`backend/routes/api.php`), and so are the buyer
/// marketplace and seller verification routes, so those three groups exist
/// below — and nothing else.
library;

abstract final class ApiConstants {
  /// Laravel expects and returns JSON.
  static const String contentTypeJson = 'application/json';

  /// Sent on every request so Laravel returns JSON errors rather than an HTML
  /// error page. Without this, a 500 renders as unparseable HTML and surfaces
  /// as a confusing parse failure.
  static const String acceptJson = 'application/json';

  /// Sanctum personal access token header.
  static const String authorizationHeader = 'Authorization';

  /// Header prefix required by Laravel Sanctum for personal access tokens.
  static const String bearerPrefix = 'Bearer';

  /// Default request timeout.
  ///
  /// Generous enough for a cold Laravel container on a laptop, short enough
  /// that a hung request does not leave the UI spinning indefinitely.
  static const Duration defaultTimeout = Duration(seconds: 30);

  /// Storage key for the Sanctum bearer token inside secure storage.
  ///
  /// The Admin Web uses `localStorage['admin_token']`. Mobile uses a different
  /// store and a different key, because these are different clients with
  /// different lifetimes — not because the token format differs.
  static const String tokenStorageKey = 'agrobenta_api_token';
}

/// Buyer marketplace endpoints, relative to the API root.
///
/// These are the routes implemented in `backend/routes/api.php`. They are the
/// buyer read-only surface and are entirely separate from `/admin/listings*`,
/// which is the Admin Web's flow and is not part of this app's contract.
///
/// Both require a `mobile`-ability Sanctum token. There is no seller listing
/// group here: listing creation and management are a later phase (GAP-09), and
/// `/api/livestock` is **not** a path this app ever calls.
abstract final class MarketplaceEndpoints {
  /// `GET` — browse active listings. 200, paginated envelope.
  ///
  /// Query parameters are built by `MarketplaceService` from an explicit
  /// allow-list of the fields `IndexListingRequest` validates. `status` is
  /// deliberately absent: the server rejects it with a 422, because marketplace
  /// visibility is active-only by construction ([D-02] rule 9) and never a
  /// client-selected filter.
  static const String browse = '/listings';

  /// `GET` — one listing's detail. 200, plain envelope.
  ///
  /// [id] is appended to build the path. It is a selector, not proof of
  /// ownership: the server re-checks visibility and answers 404 for a listing
  /// the caller may not see.
  static String detail(int id) => '/listings/$id';

  /// Page size used when the caller does not ask for a specific one.
  ///
  /// Matches the server default, so the first request is an ordinary one rather
  /// than a request that happens to agree with the default.
  static const int defaultPerPage = 15;

  /// Largest page the server will serve.
  ///
  /// `IndexListingRequest` validates `per_page` with `between:1,50`, so
  /// anything above this is rejected with a 422. `MarketplaceRepository`
  /// clamps to this rather than letting a screen discover the limit by
  /// provoking an error.
  static const int maxPerPage = 50;
}

/// Seller verification endpoints, relative to the API root.
///
/// These are the routes implemented in `backend/routes/api.php` for the caller's
/// **own** verification. They are entirely separate from
/// `/admin/seller-verifications*`, which is the Admin Web's review queue: an
/// admin token cannot reach these routes, and nothing here lists, approves or
/// rejects a record.
///
/// Neither endpoint takes an id. The record is always resolved from the
/// authenticated user, which is what makes "read your own verification" a path
/// that cannot be pointed at somebody else's account.
abstract final class SellerVerificationEndpoints {
  /// `GET` — the caller's most recent verification. 200, plain envelope.
  ///
  /// A `404` here means the user has never submitted, which is the normal first
  /// state and not an error to apologise for.
  static const String mine = '/seller-verification/me';

  /// `POST` — submit a verification. 201, plain envelope.
  ///
  /// Creates a new record; a rejected verification is resubmitted by filing
  /// again, never by updating the rejected row (functional documentation §3.2).
  /// Refused with a `409` while a verification is open, and with a `403` for an
  /// account that is already an approved seller.
  static const String submit = '/seller-verification';

  /// The field names `SubmitSellerVerificationRequest` accepts.
  ///
  /// Anything else is `prohibited` server-side and answers `422`. Listed here so
  /// the service's body is visibly an allow-list of exactly this set, and so a
  /// reader does not have to open the Form Request to know what a submission may
  /// contain.
  static const List<String> writableFields = <String>[
    'business_name',
    'business_location',
    'business_description',
    'id_document_ref',
  ];
}

/// Mobile authentication endpoints, relative to the API root.
///
/// These are the routes implemented in `backend/routes/api.php`. They are
/// separate from `/admin/auth/*`, which is the Admin Web's flow and is not part
/// of this app's contract.
///
/// `me` and `logout` require a `mobile`-ability Sanctum token; `register` and
/// `login` are unauthenticated and are throttled server-side.
abstract final class AuthEndpoints {
  /// `POST` — creates a buyer account and returns a mobile token. 201.
  static const String register = '/auth/register';

  /// `POST` — exchanges credentials for a mobile token. 200.
  static const String login = '/auth/login';

  /// `GET` — the authenticated user's own resource. 200.
  static const String me = '/auth/me';

  /// `POST` — revokes the caller's current mobile token. 200.
  static const String logout = '/auth/logout';
}
