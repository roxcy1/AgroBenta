import 'dart:convert';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/features/inquiries/state/inquiry_controller.dart';
import 'package:agrobenta_mobile/features/inquiries/state/received_inquiries_controller.dart';
import 'package:agrobenta_mobile/repositories/inquiry_repository.dart';
import 'package:agrobenta_mobile/services/inquiry_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'auth_fakes.dart';

/// A `MobileInquiryResource` payload exactly as the backend serialises one.
///
/// Field names, nullability and value spellings are copied from
/// `backend/app/Http/Resources/MobileInquiryResource.php`. A test that passes
/// against this fixture is asserting against the real contract, not a guess.
///
/// There is deliberately no `status`, `buyer` or `seller` key — the resource
/// does not send them, so a fixture that added one would let the model grow a
/// field the API never sends (mobile/AGENTS.md §A).
Map<String, dynamic> inquiryJson({
  Object? id = 5,
  Map<String, dynamic>? listing,
  String? subject = 'General Inquiry',
  String message = 'Is this one still available?',
  Object? purchaseInterest = true,
  Object? transactionMethod = 'direct_deal',
  Object? deliveryMethod = 'buyer_pickup',
  Object? deliveryFee = '1500.00',
  Object? contactMethod = 'in_app_message',
  Object? preferredSchedule = '2026-10-25',
  Object? createdAt = '2026-10-19T08:15:00.000000Z',
}) {
  return <String, dynamic>{
    'id': id,
    'listing': listing ?? inquiryListingJson(),
    'subject': subject,
    'message': message,
    'purchase_interest': purchaseInterest,
    'transaction_method': transactionMethod,
    'delivery_method': deliveryMethod,
    'delivery_fee': deliveryFee,
    'contact_method': contactMethod,
    'preferred_schedule': preferredSchedule,
    'created_at': createdAt,
  };
}

/// A `SellerInquiryResource` payload exactly as the backend serialises one.
///
/// Copied from `backend/app/Http/Resources/SellerInquiryResource.php`. There is
/// deliberately no `status`: the seller-facing resource omits it, and a fixture
/// that added one would let the model grow a field the API never sends.
Map<String, dynamic> sellerInquiryJson({
  Object? id = 5,
  Map<String, dynamic>? buyer,
  Map<String, dynamic>? listing,
  String? subject = 'General Inquiry',
  String message = 'Is this one still available?',
  Object? purchaseInterest = true,
  Object? transactionMethod = 'direct_deal',
  Object? deliveryMethod = 'buyer_pickup',
  Object? deliveryFee = '1500.00',
  Object? contactMethod = 'in_app_message',
  Object? preferredSchedule = '2026-10-25',
  Object? createdAt = '2026-10-19T08:15:00.000000Z',
}) {
  return <String, dynamic>{
    'id': id,
    'buyer': buyer ?? inquiryBuyerJson(),
    'listing': listing ?? inquiryListingJson(),
    'subject': subject,
    'message': message,
    'purchase_interest': purchaseInterest,
    'transaction_method': transactionMethod,
    'delivery_method': deliveryMethod,
    'delivery_fee': deliveryFee,
    'contact_method': contactMethod,
    'preferred_schedule': preferredSchedule,
    'created_at': createdAt,
  };
}

/// The buyer projection: identity and display name only, never an email.
Map<String, dynamic> inquiryBuyerJson({
  Object? id = 9,
  String name = 'Maria Santos',
}) {
  return <String, dynamic>{'id': id, 'name': name};
}

/// The embedded listing snapshot: `id`, `livestock_type`, `breed` — the same
/// narrow shape `MobileTransactionResource` echoes.
Map<String, dynamic> inquiryListingJson({
  Object? id = 12,
  String livestockType = 'Cattle',
  String breed = 'Holstein',
}) {
  return <String, dynamic>{
    'id': id,
    'livestock_type': livestockType,
    'breed': breed,
  };
}

const Map<String, String> _jsonHeaders = <String, String>{
  'content-type': 'application/json',
};

/// The `201` that `POST /api/inquiries` answers with, plain envelope —
/// `InquiryController@store` returns it verbatim.
http.Response inquiryCreatedResponse({Map<String, dynamic>? inquiry}) {
  return http.Response(
    jsonEncode(
      successEnvelope(message: 'Inquiry sent.', data: inquiry ?? inquiryJson()),
    ),
    201,
    headers: _jsonHeaders,
  );
}

/// The `200` that `GET /api/seller/inquiries` answers with.
http.Response sellerInquiryListResponse({
  List<Map<String, dynamic>>? inquiries,
  int currentPage = 1,
  int lastPage = 1,
  int perPage = 15,
  int? total,
}) {
  final List<Map<String, dynamic>> items =
      inquiries ?? <Map<String, dynamic>>[sellerInquiryJson()];
  return http.Response(
    jsonEncode(
      successEnvelope(
        data: <String, dynamic>{
          'inquiries': items,
          'pagination': <String, dynamic>{
            'current_page': currentPage,
            'last_page': lastPage,
            'per_page': perPage,
            'total': total ?? items.length,
          },
        },
      ),
    ),
    200,
    headers: _jsonHeaders,
  );
}

/// A `422` with per-field errors, as `StoreInquiryRequest` produces it.
http.Response inquiryValidationResponse({
  Map<String, Object> errors = const <String, Object>{
    'message': <String>['The message must not be greater than 500 characters.'],
  },
}) {
  return http.Response(
    jsonEncode(validationErrorBody(errors: errors)),
    422,
    headers: _jsonHeaders,
  );
}

/// The `409` a listing that exists but is not open to inquiries answers with
/// (not active, or the caller's own). `abort(409, ...)` carries
/// `{ "message": "..." }`.
http.Response inquiryConflictResponse({
  String message = 'This listing is not open to inquiries.',
}) {
  return http.Response(
    jsonEncode(<String, String>{'message': message}),
    409,
    headers: _jsonHeaders,
  );
}

/// The `404` for an id that does not exist, with Laravel's `abort(404, ...)`
/// bare-JSON-string body — the same shape `listingNotFoundResponse` models.
http.Response inquiryNotFoundResponse({String message = 'Listing not found.'}) {
  return http.Response(jsonEncode(message), 404, headers: _jsonHeaders);
}

/// A `500`, for failures that are neither validation nor state conflicts.
http.Response inquiryServerErrorResponse({String message = 'Server error.'}) {
  return http.Response(
    jsonEncode(<String, String>{'message': message}),
    500,
    headers: _jsonHeaders,
  );
}

/// The service over a mock transport — the layer that owns the body
/// allow-list, and therefore what a request-shape test should drive.
InquiryService buildInquiryService(
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
  return InquiryService(client);
}

/// The repository over a mock transport, built through the same [ApiClient]
/// the app uses so envelope unwrapping, the bearer token and error translation
/// are exercised exactly as production does.
InquiryRepository buildInquiryRepository(
  FakeTokenStore tokenStore,
  Future<http.Response> Function(RecordedRequest request) handler, {
  List<RecordedRequest>? recorded,
}) {
  return InquiryRepository(
    buildInquiryService(tokenStore, handler, recorded: recorded),
  );
}

/// A controller over a mock transport: real service, real repository, real
/// controller, fake HTTP.
InquiryController buildInquiryController(
  FakeTokenStore tokenStore,
  Future<http.Response> Function(RecordedRequest request) handler, {
  List<RecordedRequest>? recorded,
}) {
  return InquiryController(
    buildInquiryRepository(tokenStore, handler, recorded: recorded),
  );
}

/// The received-inquiries controller over a mock transport.
ReceivedInquiriesController buildReceivedInquiriesController(
  FakeTokenStore tokenStore,
  Future<http.Response> Function(RecordedRequest request) handler, {
  List<RecordedRequest>? recorded,
}) {
  return ReceivedInquiriesController(
    buildInquiryRepository(tokenStore, handler, recorded: recorded),
  );
}
