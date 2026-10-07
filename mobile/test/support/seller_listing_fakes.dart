import 'dart:convert';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/features/seller_listings/state/seller_listing_controller.dart';
import 'package:agrobenta_mobile/repositories/seller_listing_repository.dart';
import 'package:agrobenta_mobile/services/seller_listing_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'auth_fakes.dart';
import 'marketplace_fakes.dart';

export 'auth_fakes.dart' show FakeTokenStore, RecordedRequest;
export 'marketplace_fakes.dart'
    show
        listingJson,
        marketplacePageJson,
        sellerJson,
        unauthorizedResponse,
        forbiddenResponse,
        validationResponse,
        listingNotFoundResponse;

/// A successful `GET /api/seller/listings` response.
///
/// The seller list uses the **same envelope** as the marketplace list —
/// `listings` plus a four-key `pagination` object, per contract §3.2 — so the
/// marketplace page fixture is reused rather than a near-copy that could drift.
http.Response sellerListingListResponse({
  List<Map<String, dynamic>>? listings,
  int currentPage = 1,
  int lastPage = 1,
  int perPage = 15,
  int total = 1,
  int statusCode = 200,
}) => marketplaceListResponse(
  listings: listings,
  currentPage: currentPage,
  lastPage: lastPage,
  perPage: perPage,
  total: total,
  statusCode: statusCode,
);

/// A successful create, update or submit response: one listing resource.
http.Response sellerListingResponse({
  Map<String, dynamic>? listing,
  int statusCode = 200,
  String? message,
}) => http.Response(
  jsonEncode(successEnvelope(data: listing ?? listingJson(), message: message)),
  statusCode,
  headers: <String, String>{'content-type': 'application/json'},
);

/// A successful `DELETE` response.
///
/// The endpoint answers `200` with a message and **no `data`**, so this fixture
/// deliberately has a null payload — a test that passes here is asserting the
/// client tolerates the shape the server actually returns.
http.Response sellerListingDeletedResponse({
  String message = 'Listing deleted.',
  int statusCode = 200,
}) => http.Response(
  jsonEncode(successEnvelope(message: message)),
  statusCode,
  headers: <String, String>{'content-type': 'application/json'},
);

/// The `409` a lifecycle violation produces.
///
/// `SellerListingService` answers a bare-string body with this message, so the
/// fixture is the same shape.
http.Response listingConflictResponse({
  String message = 'This listing is not in a state that allows that action.',
}) => http.Response(jsonEncode(message), 409);

/// A `403`, as the `seller` middleware answers a non-approved account.
http.Response notApprovedSellerResponse({
  String message = 'This action is unauthorized.',
}) => http.Response(jsonEncode(message), 403);

/// The seller-listing repository over a mock transport.
SellerListingRepository buildSellerListingRepository(
  FakeTokenStore tokenStore,
  Future<http.Response> Function(RecordedRequest request) handler, {
  List<RecordedRequest>? recorded,
}) {
  final ApiClient client = ApiClient(
    tokenStorage: tokenStore,
    httpClient: MockClient((http.Request request) async {
      final RecordedRequest entry = RecordedRequest(request);
      recorded?.add(entry);
      return handler(entry);
    }),
  );
  return SellerListingRepository(SellerListingService(client));
}

/// The whole seller-listing stack over a mock transport: real service, real
/// repository, real controller, fake HTTP.
///
/// Built through the same [ApiClient] the app uses, so envelope unwrapping, the
/// bearer token and the error-kind translation are all exercised rather than
/// stubbed away.
SellerListingController buildSellerListingController(
  FakeTokenStore tokenStore,
  Future<http.Response> Function(RecordedRequest request) handler, {
  List<RecordedRequest>? recorded,
}) {
  return SellerListingController(
    buildSellerListingRepository(tokenStore, handler, recorded: recorded),
  );
}

/// A [SellerListingController] over a handler, with a token store attached.
({
  SellerListingController controller,
  FakeTokenStore tokenStore,
  List<RecordedRequest> recorded,
})
buildRecordedController(
  Future<http.Response> Function(RecordedRequest request) handler,
) {
  final FakeTokenStore tokenStore = FakeTokenStore('1|test-mobile-token');
  final List<RecordedRequest> recorded = <RecordedRequest>[];
  return (
    controller: buildSellerListingController(
      tokenStore,
      handler,
      recorded: recorded,
    ),
    tokenStore: tokenStore,
    recorded: recorded,
  );
}
