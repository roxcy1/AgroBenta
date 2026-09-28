import 'dart:convert';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/features/seller_verification/state/seller_verification_controller.dart';
import 'package:agrobenta_mobile/repositories/seller_verification_repository.dart';
import 'package:agrobenta_mobile/services/seller_verification_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'auth_fakes.dart';

/// A `MobileSellerVerificationResource` payload exactly as the backend
/// serialises one.
///
/// Field names, nullability and value spellings are copied from
/// `backend/app/Http/Resources/MobileSellerVerificationResource.php`. A test that
/// passes against this fixture is asserting against the real contract, not a
/// guess.
///
/// Note what is absent: no `seller`, no `reviewer`, no `user_id`, no
/// `created_at`/`updated_at`. Their absence is the contract, and
/// `seller_verification_test.dart` asserts the model rejects them if they appear.
Map<String, dynamic> sellerVerificationJson({
  Object? id = 4,
  String businessName = 'Rizal Farms',
  Object? businessLocation = 'Mabalacat, Pampanga',
  Object? businessDescription = 'Family-run cattle farm, trading since 2011.',
  Object? idDocumentRef = 'PHL-ID-88213',
  String status = 'submitted',
  Object? adminNote,
  Object? submittedAt = '2026-09-26T09:30:00.000000Z',
  Object? reviewedAt,
}) {
  return <String, dynamic>{
    'id': id,
    'business_name': businessName,
    'business_location': businessLocation,
    'business_description': businessDescription,
    'id_document_ref': idDocumentRef,
    'status': status,
    'admin_note': adminNote,
    'submitted_at': submittedAt,
    'reviewed_at': reviewedAt,
  };
}

/// A successful `GET /api/seller-verification/me`.
http.Response sellerVerificationResponse({
  Map<String, dynamic>? verification,
  int statusCode = 200,
}) => http.Response(
  jsonEncode(successEnvelope(data: verification ?? sellerVerificationJson())),
  statusCode,
  headers: <String, String>{'content-type': 'application/json'},
);

/// A successful `POST /api/seller-verification`, which answers `201`.
http.Response sellerVerificationCreatedResponse({
  Map<String, dynamic>? verification,
  int statusCode = 201,
}) => http.Response(
  jsonEncode(successEnvelope(data: verification ?? sellerVerificationJson())),
  statusCode,
  headers: <String, String>{'content-type': 'application/json'},
);

/// The `404` a user who has never submitted gets, with Laravel's
/// `abort(404, ...)` bare-JSON-string body.
http.Response sellerVerificationNotFoundResponse({
  String message = 'You have not submitted a seller verification.',
}) => http.Response(jsonEncode(message), 404);

/// The `409` a second open application produces.
http.Response sellerVerificationConflictResponse({
  String message = 'A seller verification is already open for review.',
}) => http.Response(jsonEncode(message), 409);

/// The `403` an already-approved seller gets when submitting.
http.Response sellerVerificationForbiddenResponse({
  String message = 'This account is already an approved seller.',
}) => http.Response(jsonEncode(message), 403);

/// A `422` with per-field errors, as `SubmitSellerVerificationRequest` produces.
http.Response sellerVerificationValidationResponse({
  Map<String, Object> errors = const <String, Object>{
    'business_name': <String>['The business name is required.'],
  },
}) => http.Response(
  jsonEncode(validationErrorBody(errors: errors)),
  422,
  headers: <String, String>{'content-type': 'application/json'},
);

/// A `422` produced by a **prohibited** field, which is how the backend answers
/// a client that tries to set a server-owned value.
http.Response prohibitedFieldResponse({String field = 'seller_capability'}) =>
    http.Response(
      jsonEncode(
        validationErrorBody(
          errors: <String, Object>{
            field: <String>['The $field field is prohibited.'],
          },
        ),
      ),
      422,
      headers: <String, String>{'content-type': 'application/json'},
    );

/// The service over a mock transport that records every request.
SellerVerificationService buildSellerVerificationService(
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
  return SellerVerificationService(client);
}

/// The repository over a mock transport.
SellerVerificationRepository buildSellerVerificationRepository(
  FakeTokenStore tokenStore,
  Future<http.Response> Function(RecordedRequest request) handler, {
  List<RecordedRequest>? recorded,
}) =>
    SellerVerificationRepository(
      buildSellerVerificationService(tokenStore, handler, recorded: recorded),
    );

/// The whole seller verification stack over a mock transport, which is what most
/// tests want: real service, real repository, real controller, fake HTTP.
///
/// Built through the same [ApiClient] the app uses, so the tests exercise the
/// envelope unwrapping, the bearer token and the `404`/`409` translation exactly
/// as production does rather than stubbing them away.
SellerVerificationController buildSellerVerificationController(
  FakeTokenStore tokenStore,
  Future<http.Response> Function(RecordedRequest request) handler, {
  List<RecordedRequest>? recorded,
  Future<bool> Function()? onCapabilityMayHaveChanged,
}) {
  return SellerVerificationController(
    buildSellerVerificationRepository(tokenStore, handler, recorded: recorded),
    onCapabilityMayHaveChanged: onCapabilityMayHaveChanged,
  );
}

/// A controller whose read returns [verification], with no HTTP.
SellerVerificationController controllerReturning(
  Map<String, dynamic>? verification, {
  Future<bool> Function()? onCapabilityMayHaveChanged,
}) {
  final ApiClient client = ApiClient(
    tokenStorage: FakeTokenStore('token'),
    httpClient: MockClient(
      (http.Request request) async =>
          verification == null
              ? sellerVerificationNotFoundResponse()
              : sellerVerificationResponse(verification: verification),
    ),
  );
  return SellerVerificationController(
    SellerVerificationRepository(SellerVerificationService(client)),
    onCapabilityMayHaveChanged: onCapabilityMayHaveChanged,
  );
}
