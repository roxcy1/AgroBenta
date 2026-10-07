import 'dart:convert';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/features/marketplace/state/marketplace_controller.dart';
import 'package:agrobenta_mobile/repositories/marketplace_repository.dart';
import 'package:agrobenta_mobile/services/marketplace_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'auth_fakes.dart';

/// A `MobileListingResource` payload exactly as the backend serialises one.
///
/// Field names, nullability and value spellings are copied from
/// `backend/app/Http/Resources/MobileListingResource.php`. A test that passes
/// against this fixture is asserting against the real contract, not a guess.
///
/// The decimal columns are parameters rather than fixed strings so a test can
/// reproduce the MySQL/SQLite divergence the backend actually has: MySQL returns
/// `"42500.00"` for a `decimal(14,2)`, while SQLite returns the number
/// `42500.0`. Both must parse to the same [Listing].
Map<String, dynamic> listingJson({
  Object? id = 12,
  String livestockType = 'Cattle',
  String breed = 'Holstein',
  Object? ageValue = '18.0',
  Object? ageUnit = 'month',
  Object? gender = 'female',
  Object? weightValue = '320.50',
  Object? weightUnit = 'kg',
  Object? quantity = 4,
  Object? askingPrice = '42500.00',
  String location = 'Mabalacat, Pampanga',
  Object? healthStatus = 'Healthy',
  Object? vaccination = 'Vaccinated',
  String shortDescription = 'Healthy Holstein heifers, ready for breeding.',
  Object? additionalNotes = 'Delivered on weekends only.',
  List<Object?>? photos,
  String status = 'active',
  Object? createdAt = '2026-09-20T08:15:00.000000Z',
  Object? updatedAt = '2026-09-20T08:15:00.000000Z',
  Map<String, dynamic>? seller,
}) {
  return <String, dynamic>{
    'id': id,
    'seller': seller ?? sellerJson(),
    'livestock_type': livestockType,
    'breed': breed,
    'age_value': ageValue,
    'age_unit': ageUnit,
    'gender': gender,
    'weight_value': weightValue,
    'weight_unit': weightUnit,
    'quantity': quantity,
    'asking_price': askingPrice,
    'location': location,
    'health_status': healthStatus,
    'vaccination': vaccination,
    'short_description': shortDescription,
    'additional_notes': additionalNotes,
    'photos': photos ?? <Object?>[],
    'status': status,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
}

/// The `MobileSellerResource` projection: `id` and `name`, nothing else.
Map<String, dynamic> sellerJson({
  Object? id = 3,
  String name = 'Rizal Farms',
}) => <String, dynamic>{'id': id, 'name': name};

/// The `data` payload of `GET /api/listings`.
///
/// The hand-rolled paginated shape from contract §3.2 — `listings` plus a
/// four-key `pagination` object, not Laravel's nested `data` array.
Map<String, dynamic> marketplacePageJson({
  List<Map<String, dynamic>>? listings,
  int currentPage = 1,
  int lastPage = 1,
  int perPage = 15,
  int total = 1,
}) {
  return <String, dynamic>{
    'listings': listings ?? <Map<String, dynamic>>[listingJson()],
    'pagination': <String, dynamic>{
      'current_page': currentPage,
      'last_page': lastPage,
      'per_page': perPage,
      'total': total,
    },
  };
}

/// A successful `GET /api/listings` HTTP response.
http.Response marketplaceListResponse({
  List<Map<String, dynamic>>? listings,
  int currentPage = 1,
  int lastPage = 1,
  int perPage = 15,
  int total = 1,
  int statusCode = 200,
}) => http.Response(
  jsonEncode(
    successEnvelope(
      data: marketplacePageJson(
        listings: listings,
        currentPage: currentPage,
        lastPage: lastPage,
        perPage: perPage,
        total: total,
      ),
    ),
  ),
  statusCode,
  headers: <String, String>{'content-type': 'application/json'},
);

/// A successful `GET /api/listings/{id}` HTTP response.
http.Response listingDetailResponse({
  Map<String, dynamic>? listing,
  int statusCode = 200,
}) => http.Response(
  jsonEncode(successEnvelope(data: listing ?? listingJson())),
  statusCode,
  headers: <String, String>{'content-type': 'application/json'},
);

/// The `404` a hidden listing produces, with Laravel's `abort(404, ...)`
/// bare-JSON-string body.
http.Response listingNotFoundResponse({
  String message = 'Listing not found.',
}) => http.Response(jsonEncode(message), 404);

/// A `401`, as the API answers an unauthenticated or revoked request.
http.Response unauthorizedResponse({String message = 'Unauthenticated.'}) =>
    http.Response(jsonEncode(message), 401);

/// A `403`, as the API answers a token without the `mobile` ability.
http.Response forbiddenResponse({
  String message = 'This action is unauthorized.',
}) => http.Response(jsonEncode(message), 403);

/// A `422` with per-field errors, as `IndexListingRequest` produces.
http.Response validationResponse({
  Map<String, Object> errors = const <String, Object>{
    'per_page': <String>['The per page must not be greater than 50.'],
  },
}) => http.Response(
  jsonEncode(validationErrorBody(errors: errors)),
  422,
  headers: <String, String>{'content-type': 'application/json'},
);

/// The repository over a mock transport, for tests that need to drive a
/// per-screen controller rather than the list one.
MarketplaceRepository buildMarketplaceRepository(
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
  return MarketplaceRepository(MarketplaceService(client));
}

/// The whole marketplace stack over a mock transport, which is what most tests
/// want: real service, real repository, real controller, fake HTTP.
///
/// Built through the same [ApiClient] the app uses, so the tests exercise the
/// envelope unwrapping, the bearer token and the `404` translation exactly as
/// production does rather than stubbing them away.
MarketplaceController buildMarketplaceController(
  FakeTokenStore tokenStore,
  Future<http.Response> Function(RecordedRequest request) handler, {
  List<RecordedRequest>? recorded,
}) {
  return MarketplaceController(
    buildMarketplaceRepository(tokenStore, handler, recorded: recorded),
  );
}

/// A [MarketplaceController] with a single canned successful page and no HTTP.
MarketplaceController controllerReturning(List<Map<String, dynamic>> listings) {
  final ApiClient client = ApiClient(
    tokenStorage: FakeTokenStore('token'),
    httpClient: MockClient(
      (http.Request request) async =>
          marketplaceListResponse(listings: listings),
    ),
  );
  return MarketplaceController(
    MarketplaceRepository(MarketplaceService(client)),
  );
}
