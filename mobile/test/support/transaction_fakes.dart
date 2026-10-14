import 'dart:convert';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/features/transactions/state/transaction_detail_controller.dart';
import 'package:agrobenta_mobile/features/transactions/state/transactions_controller.dart';
import 'package:agrobenta_mobile/models/transaction.dart';
import 'package:agrobenta_mobile/repositories/transaction_repository.dart';
import 'package:agrobenta_mobile/services/transaction_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'auth_fakes.dart';

/// A `MobileTransactionResource` payload exactly as the backend serialises one.
///
/// Field names, nullability and value spellings are copied from
/// `backend/app/Http/Resources/MobileTransactionResource.php`. A test that
/// passes against this fixture is asserting against the real contract, not a
/// guess.
///
/// [totalAmount] is a decimal **string** exactly as `decimal(14,2)` columns
/// serialise over the API; it is display-only and must never be parsed for
/// arithmetic in the client.
Map<String, dynamic> transactionJson({
  Object? id = 1,
  String role = 'buyer',
  Map<String, dynamic>? listing,
  Map<String, dynamic>? counterparty,
  Object? quantity = 1,
  Object? totalAmount = '42500.00',
  String status = 'pending',
  Object? createdAt = '2026-10-01T08:15:00.000000Z',
  Object? updatedAt = '2026-10-01T08:15:00.000000Z',
}) {
  return <String, dynamic>{
    'id': id,
    'role': role,
    'listing': listing ?? transactionListingJson(),
    'counterparty': counterparty ?? transactionCounterpartyJson(),
    'quantity': quantity,
    'total_amount': totalAmount,
    'status': status,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
}

/// The embedded `listing` snapshot: identity, species, breed and photos only.
Map<String, dynamic> transactionListingJson({
  Object? id = 12,
  String livestockType = 'Cattle',
  String breed = 'Holstein',
  List<Object?>? photos,
}) {
  return <String, dynamic>{
    'id': id,
    'livestock_type': livestockType,
    'breed': breed,
    'photos': photos ?? <Object?>[],
  };
}

/// The counterparty projection: `{ id, name, email }`, never both parties.
Map<String, dynamic> transactionCounterpartyJson({
  Object? id = 3,
  String name = 'Rizal Farms',
  String email = 'rizal@example.test',
}) {
  return <String, dynamic>{'id': id, 'name': name, 'email': email};
}

/// The `data` payload of `GET /api/transactions` — the endpoint-specific
/// `transactions` array plus the hand-rolled four-key `pagination` object
/// from contract §3.2, same shape as `marketplacePageJson`.
Map<String, dynamic> transactionPageJson({
  List<Map<String, dynamic>>? transactions,
  int currentPage = 1,
  int lastPage = 1,
  int perPage = 15,
  int total = 1,
}) {
  return <String, dynamic>{
    'transactions': transactions ?? <Map<String, dynamic>>[transactionJson()],
    'pagination': <String, dynamic>{
      'current_page': currentPage,
      'last_page': lastPage,
      'per_page': perPage,
      'total': total,
    },
  };
}

const Map<String, String> _jsonHeaders = <String, String>{
  'content-type': 'application/json',
};

/// A successful `GET /api/transactions` HTTP response.
http.Response transactionListResponse({
  List<Map<String, dynamic>>? transactions,
  int currentPage = 1,
  int lastPage = 1,
  int perPage = 15,
  int total = 1,
  int statusCode = 200,
}) {
  return http.Response(
    jsonEncode(
      successEnvelope(
        data: transactionPageJson(
          transactions: transactions,
          currentPage: currentPage,
          lastPage: lastPage,
          perPage: perPage,
          total: total,
        ),
      ),
    ),
    statusCode,
    headers: _jsonHeaders,
  );
}

/// A successful `GET /api/transactions/{id}` HTTP response.
http.Response transactionDetailResponse({
  Map<String, dynamic>? transaction,
  int statusCode = 200,
}) {
  return http.Response(
    jsonEncode(successEnvelope(data: transaction ?? transactionJson())),
    statusCode,
    headers: _jsonHeaders,
  );
}

/// The `201` that `POST /api/transactions` answers with, plain envelope.
http.Response transactionCreatedResponse({Map<String, dynamic>? transaction}) {
  return http.Response(
    jsonEncode(
      successEnvelope(
        message: 'Transaction created.',
        data: transaction ?? transactionJson(),
      ),
    ),
    201,
    headers: _jsonHeaders,
  );
}

/// The `404` a hidden or foreign transaction produces, with Laravel's
/// `abort(404, ...)` bare-JSON-string body — the same shape
/// `listingNotFoundResponse` models.
http.Response transactionNotFoundResponse({
  String message = 'Transaction not found.',
}) {
  return http.Response(jsonEncode(message), 404, headers: _jsonHeaders);
}

/// The `409` `POST /api/transactions/{id}/cancel` answers with when the
/// record has already left `pending`. Contract §"error bodies": an
/// `abort(409, ...)` carries `{ "message": "..." }`.
http.Response transactionConflictResponse({
  String message = 'Only a pending transaction can be cancelled.',
}) {
  return http.Response(
    jsonEncode(<String, String>{'message': message}),
    409,
    headers: _jsonHeaders,
  );
}

/// A `500`, for first-page and cancel failures that are not state conflicts.
http.Response transactionServerErrorResponse({
  String message = 'Server error.',
}) {
  return http.Response(
    jsonEncode(<String, String>{'message': message}),
    500,
    headers: _jsonHeaders,
  );
}

/// The repository over a mock transport, built through the same [ApiClient]
/// the app uses so envelope unwrapping, the bearer token and error translation
/// are exercised exactly as production does.
TransactionRepository buildTransactionRepository(
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
  return TransactionRepository(TransactionService(client));
}

/// A list-tab controller over a mock transport: real service, real
/// repository, real controller, fake HTTP.
TransactionsController buildTransactionsController(
  FakeTokenStore tokenStore,
  Future<http.Response> Function(RecordedRequest request) handler, {
  TransactionStatus status = TransactionStatus.pending,
  List<RecordedRequest>? recorded,
}) {
  return TransactionsController(
    buildTransactionRepository(tokenStore, handler, recorded: recorded),
    status,
  );
}

/// A detail-screen controller over a mock transport.
TransactionDetailController buildTransactionDetailController(
  FakeTokenStore tokenStore,
  Future<http.Response> Function(RecordedRequest request) handler, {
  int transactionId = 1,
  List<RecordedRequest>? recorded,
}) {
  return TransactionDetailController(
    buildTransactionRepository(tokenStore, handler, recorded: recorded),
    transactionId,
  );
}
