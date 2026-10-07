import '../core/constants/api_constants.dart';
import '../core/network/api_client.dart';
import '../models/listing.dart';
import '../models/marketplace_page.dart';

/// The seller listing management API surface.
///
/// One method per endpoint in contract §5.4, and nothing else. No token
/// handling, no persistence, no error translation beyond what [ApiClient] already
/// does — those belong to `SellerListingRepository`.
///
/// ## What cannot leave the device
///
/// The body of every write is filtered through
/// [SellerListingEndpoints.writableFields] in [writableBody], so the request is
/// an **allow-list** rather than a set of fields this file happens to remember to
/// pass. `status` and `seller_id` are the two that matter: the server marks both
/// `prohibited` and answers `422`, and no path through this class can construct
/// either, so a client that grows a new field on [Listing] cannot accidentally
/// start asserting ownership or publishing a listing.
///
/// `photos` is excluded from that allow-list for a different reason — not a rule
/// but an undecided contract. D-10 leaves both the upload mechanism and the
/// stored representation open, so a body with a photo path would encode an
/// answer nobody has given. The seller form has no photo field at all.
class SellerListingService {
  const SellerListingService(this._apiClient);

  final ApiClient _apiClient;

  /// `GET /seller/listings` — one page of the caller's own listings.
  ///
  /// [statusFilter] narrows to a single status, which the marketplace endpoint
  /// does not allow at all: a seller needs to find their drafts and their
  /// listings awaiting review, and those are exactly the records the marketplace
  /// never returns. [search] is matched server-side against `livestock_type`,
  /// `breed` and `location`, so it narrows the whole result set.
  ///
  /// Blank strings are treated as absent, so the default request is a bare
  /// `GET /seller/listings` rather than one carrying empty filters.
  ///
  /// Throws [ApiException]:
  ///  * `unauthorized` on a `401`; `ApiClient` has cleared the token and the auth
  ///    gate takes the app to sign-in.
  ///  * `forbidden` on a `403` — the account is not an approved seller. The
  ///    entry point is gated on the caller's capability so this should not be
  ///    reachable, but it is a real state (a capability revoked server-side) and
  ///    is reported rather than treated as an empty list.
  ///  * `validation` on a `422`, which for a GET means a filter the server
  ///    rejected: a client bug, not something to bury.
  Future<MarketplacePage> listMine({
    String? statusFilter,
    String? search,
    int page = 1,
    int perPage = SellerListingEndpoints.defaultPerPage,
  }) {
    return _apiClient.get<MarketplacePage>(
      SellerListingEndpoints.mine,
      query: <String, dynamic>{
        // Explicit allow-list, same reasoning as the body filter below.
        if (_present(statusFilter)) 'status': statusFilter!.trim(),
        if (_present(search)) 'search': search!.trim(),
        'page': page,
        'per_page': perPage,
      },
      parse: (Object? data) =>
          MarketplacePage.fromJson(_asObject(data, 'GET /seller/listings')),
    );
  }

  /// `POST /seller/listings` — create a draft.
  ///
  /// [fields] is filtered by [writableBody] and blank optional values are dropped
  /// by the caller, so the request carries only what the seller actually filled
  /// in. The response is the stored listing, so the client does not need a
  /// second request to populate its list.
  ///
  /// Throws [ApiException]:
  ///  * `validation` on a `422`, carrying per-field messages for the form.
  ///  * `forbidden` on a `403` — not an approved seller.
  Future<Listing> create(Map<String, dynamic> fields) {
    return _apiClient.post<Listing>(
      SellerListingEndpoints.create,
      body: writableBody(fields),
      parse: (Object? data) =>
          Listing.fromJson(_asObject(data, 'POST /seller/listings')),
    );
  }

  /// `PATCH /seller/listings/{id}` — edit a listing the caller owns.
  ///
  /// A true PATCH: a field absent from [fields] is left alone by the server. The
  /// server permits the edit only while the listing is a `draft` or `active`, and
  /// answers `409` otherwise.
  ///
  /// Throws [ApiException]:
  ///  * `validation` on a `422`, carrying per-field messages for the form.
  ///  * `conflict` on a `409` — the listing is no longer editable, typically
  ///    because it was submitted for review and is now with an administrator.
  ///  * `notFound` on a `404` — it is not the caller's listing, or it is gone.
  Future<Listing> update(int id, Map<String, dynamic> fields) {
    return _apiClient.patch<Listing>(
      SellerListingEndpoints.update(id),
      body: writableBody(fields),
      parse: (Object? data) =>
          Listing.fromJson(_asObject(data, 'PATCH /seller/listings/$id')),
    );
  }

  /// `POST /seller/listings/{id}/submit` — move a draft into review.
  ///
  /// The only lifecycle transition a seller can make, and one-way. The server
  /// re-validates the stored listing against the create rules first, so a draft
  /// that cannot be submitted is answered `422` with per-field messages rather
  /// than queued for an administrator to read.
  ///
  /// Throws [ApiException]:
  ///  * `conflict` on a `409` — not a draft; it is already submitted, or the
  ///    account is trying to re-submit something an administrator has decided.
  ///  * `validation` on a `422` — the stored listing is missing something.
  Future<Listing> submit(int id) {
    return _apiClient.post<Listing>(
      SellerListingEndpoints.submit(id),
      parse: (Object? data) =>
          Listing.fromJson(_asObject(data, 'POST /seller/listings/$id/submit')),
    );
  }

  /// `DELETE /seller/listings/{id}` — destroy a draft or withdrawn listing.
  ///
  /// A real deletion, and the server restricts it to a `draft` or `inactive`
  /// listing. It is **not** a deactivation: there is no seller route that takes a
  /// live listing out of sale, because `active → inactive` is an administrator
  /// decision ([D-02] rule 4).
  ///
  /// Throws [ApiException]:
  ///  * `conflict` on a `409` — the listing is live, pending or sold.
  ///  * `notFound` on a `404` — not the caller's listing, or already deleted.
  Future<void> delete(int id) {
    return _apiClient.delete<void>(
      SellerListingEndpoints.destroy(id),
      // The endpoint answers with a message and no `data`, which `ApiClient`
      // treats as a valid empty payload rather than a malformed response. The
      // value is discarded, so it is not a `null` a `void` has to return.
      parse: (_) {},
    );
  }

  /// Reduces a field map to exactly the contract's writable fields.
  ///
  /// The single choke point every write goes through. Two properties matter:
  ///
  ///  * a key that is not in [SellerListingEndpoints.writableFields] is dropped
  ///    silently rather than sent and rejected, so an accidental extra is a
  ///    client bug caught in a test instead of a `422` a seller has to interpret;
  ///  * `status` and `seller_id` therefore have no path into a body at all.
  ///
  /// A `null` **value** is kept, because null is meaningful for a nullable field;
  /// what is filtered is the *key*.
  static Map<String, dynamic> writableBody(Map<String, dynamic> fields) {
    return <String, dynamic>{
      for (final String key in SellerListingEndpoints.writableFields)
        if (fields.containsKey(key)) key: fields[key],
    };
  }

  static bool _present(String? value) =>
      value != null && value.trim().isNotEmpty;

  /// Casts an unwrapped `data` payload to a JSON object with a message that names
  /// the endpoint, instead of a bare cast error. A [FormatException] here is
  /// translated by [ApiClient] into `ApiErrorKind.malformedResponse`.
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
