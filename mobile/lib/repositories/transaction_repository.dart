import '../core/constants/api_constants.dart';
import '../models/transaction.dart';
import '../models/transaction_page.dart';
import '../services/transaction_service.dart';

/// Orchestration for the caller's transactions.
///
/// Thin by design, mirroring `MarketplaceRepository`. The one policy that
/// belongs here is the page size: the server caps `per_page` at 50 with a
/// `422` for anything higher, and that limit is a fact about the API rather
/// than about any screen. Clamping it here means no widget can discover the
/// cap by provoking an error.
///
/// Error translation is deliberately **not** done here. `ApiException.message`
/// is already curated to be displayable, so a second translation layer would
/// be a second place for wording to drift.
class TransactionRepository {
  const TransactionRepository(this._service);

  final TransactionService _service;

  /// Fetches one page of the caller's transactions.
  ///
  /// [perPage] is clamped to `1..[TransactionEndpoints.maxPerPage]`.
  Future<TransactionPage> list({
    TransactionRole? role,
    TransactionStatus? status,
    int page = 1,
    int? perPage,
  }) {
    return _service.list(
      role: role,
      status: status,
      // A page below 1 is meaningless to Laravel, which treats it as page 1.
      page: page < 1 ? 1 : page,
      perPage: _clampPerPage(perPage),
    );
  }

  /// Creates a pending transaction for the authenticated buyer.
  ///
  /// Sends only `{ listingId, quantity }`. The amount is server-derived and
  /// is read back from the created record, never computed here.
  Future<Transaction> create({required int listingId, required int quantity}) =>
      _service.create(listingId: listingId, quantity: quantity);

  /// Fetches one transaction the caller is party to.
  Future<Transaction> detail(int id) => _service.detail(id);

  /// Cancels a pending transaction. Either party, irreversible.
  Future<Transaction> cancel(int id) => _service.cancel(id);

  static int _clampPerPage(int? perPage) {
    final int requested = perPage ?? TransactionEndpoints.defaultPerPage;
    if (requested < 1) {
      return 1;
    }
    if (requested > TransactionEndpoints.maxPerPage) {
      return TransactionEndpoints.maxPerPage;
    }
    return requested;
  }
}
