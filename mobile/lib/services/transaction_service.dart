import '../core/constants/api_constants.dart';
import '../core/network/api_client.dart';
import '../models/transaction.dart';
import '../models/transaction_page.dart';

/// The transaction API surface.
///
/// Four methods, one per implemented endpoint, and nothing else. No token
/// handling, no persistence, no error translation beyond what [ApiClient]
/// already does — those belong to `TransactionRepository`.
///
/// There is deliberately **no `complete` method**. The backend answers that
/// transition with an explicit 501 (OQ-15), and a method that always errors
/// is worse than no method.
class TransactionService {
  const TransactionService(this._apiClient);

  final ApiClient _apiClient;

  /// `GET /transactions` — one page of the caller's transactions.
  ///
  /// [role] narrows to one side of the caller's own records (`buyer` or
  /// `seller`); absent means both. [status] narrows to one lifecycle state
  /// for the tabbed screen. Both are server-checked side selectors, never
  /// user selectors — `buyer_id` / `seller_id` have no path to the request.
  Future<TransactionPage> list({
    TransactionRole? role,
    TransactionStatus? status,
    int page = 1,
    int perPage = TransactionEndpoints.defaultPerPage,
  }) {
    return _apiClient.get<TransactionPage>(
      TransactionEndpoints.list,
      query: <String, dynamic>{
        // Explicit allow-list. Anything not named here has no path to the
        // request, so a field added to the model can never become a filter.
        if (role != null) 'role': role.value,
        if (status != null) 'status': status.value,
        'page': page,
        'per_page': perPage,
      },
      parse: (Object? data) =>
          TransactionPage.fromJson(_asObject(data, 'GET /transactions')),
    );
  }

  /// `POST /transactions` — create a pending transaction.
  ///
  /// The caller is the buyer ([D-15] rule 1). The body is exactly
  /// `{ listing_id, quantity }`: `buyer_id`, `seller_id`, `total_amount`
  /// and `status` are server-derived, so they are not merely unused here,
  /// they are unreachable.
  Future<Transaction> create({required int listingId, required int quantity}) {
    return _apiClient.post<Transaction>(
      TransactionEndpoints.create,
      body: <String, dynamic>{'listing_id': listingId, 'quantity': quantity},
      parse: (Object? data) =>
          Transaction.fromJson(_asObject(data, 'POST /transactions')),
    );
  }

  /// `GET /transactions/{id}` — one transaction the caller is party to.
  ///
  /// A `404` is a normal outcome: the transaction does not exist or the
  /// caller is not a party to it, and the server answers 404 for both so one
  /// pair's transactions cannot be probed.
  Future<Transaction> detail(int id) {
    return _apiClient.get<Transaction>(
      TransactionEndpoints.detail(id),
      parse: (Object? data) =>
          Transaction.fromJson(_asObject(data, 'GET /transactions/$id')),
    );
  }

  /// `POST /transactions/{id}/cancel` — cancel a pending transaction.
  ///
  /// Either party may cancel ([D-15] rule 5), pending-only, irreversible.
  /// The body allow-list is empty: the action reads no input, so nothing is
  /// sent. A `409` means the transaction already left `pending`.
  Future<Transaction> cancel(int id) {
    return _apiClient.post<Transaction>(
      TransactionEndpoints.cancel(id),
      parse: (Object? data) =>
          Transaction.fromJson(_asObject(data, 'POST /transactions/$id/cancel')),
    );
  }

  /// Casts an unwrapped `data` payload to a JSON object with a message that
  /// names the endpoint, instead of a bare cast error. A `FormatException`
  /// here is translated by `ApiClient` into `malformedResponse`.
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
