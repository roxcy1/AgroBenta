import '../core/utils/json_utils.dart';
import 'pagination.dart';
import 'transaction.dart';

/// One page of the caller's transactions plus their pagination.
///
/// Mirrors the `data` payload of `GET /api/transactions`, which uses the
/// hand-rolled paginated envelope from contract §3.2 with the
/// endpoint-specific array key `transactions`:
///
/// ```json
/// {
///   "success": true,
///   "data": {
///     "transactions": [ /* MobileTransactionResource[] */ ],
///     "pagination": { "current_page": 1, "last_page": 5, "per_page": 15, "total": 68 }
///   }
/// }
/// ```
///
/// The array key is endpoint-specific across the API and must not be
/// generalised — which is why this is a named model rather than a generic
/// `PagedResponse<T>`, same as `MarketplacePage`.
class TransactionPage {
  const TransactionPage({required this.transactions, required this.pagination});

  factory TransactionPage.fromJson(Map<String, dynamic> json) {
    return TransactionPage(
      transactions: readObjectList(
        json,
        'transactions',
      ).map(Transaction.fromJson).toList(growable: false),
      pagination: Pagination.fromJson(readObject(json, 'pagination')),
    );
  }

  /// The transactions on this page, newest first.
  ///
  /// Order is the server's: `created_at DESC, id DESC`. The app does not
  /// re-sort them, because doing so would disagree with the pagination the
  /// server computed over that same ordering.
  final List<Transaction> transactions;

  final Pagination pagination;

  /// Whether the server has another page after this one.
  bool get hasMore => pagination.hasNextPage;

  /// Whether this page carried no records.
  bool get isEmpty => transactions.isEmpty;

  @override
  String toString() =>
      'TransactionPage(${transactions.length} transactions, '
      'page ${pagination.currentPage}/${pagination.lastPage})';
}
