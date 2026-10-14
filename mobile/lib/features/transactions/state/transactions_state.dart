import '../../../models/pagination.dart';
import '../../../models/transaction.dart';

/// Where one transaction tab is in its lifecycle.
///
/// One enum for the whole list, because these are mutually exclusive
/// presentations — the same shape as `MarketplaceStatus`, minus search and
/// filters, which transactions do not have.
enum TransactionsStatus {
  /// Constructed but nothing requested yet.
  initial,

  /// The first page is in flight and there is nothing to show yet.
  loading,

  /// At least one page is loaded. The screen may still be fetching another.
  ready,

  /// A page after the first is in flight; results stay on screen.
  loadingMore,

  /// Page 1 re-queried while results are on screen (pull-to-refresh).
  refreshing,

  /// The first page failed. Nothing on screen to preserve.
  failed,
}

/// An immutable snapshot of everything one transaction tab renders from.
class TransactionsState {
  const TransactionsState({
    this.status = TransactionsStatus.initial,
    this.transactions = const <Transaction>[],
    this.pagination,
    this.errorMessage,
    this.loadMoreErrorMessage,
    this.refreshErrorMessage,
  });

  final TransactionsStatus status;

  /// Every transaction loaded so far, in server order.
  final List<Transaction> transactions;

  /// Pagination for the most recent page received.
  final Pagination? pagination;

  /// A displayable failure for the whole tab.
  final String? errorMessage;

  /// A displayable failure for a subsequent page.
  final String? loadMoreErrorMessage;

  /// A displayable failure for a pull-to-refresh that kept stale results.
  final String? refreshErrorMessage;

  int get currentPage => pagination?.currentPage ?? 0;

  bool get hasMorePages => pagination?.hasNextPage ?? false;

  bool get isEmpty => status == TransactionsStatus.ready && transactions.isEmpty;

  bool get isBusy =>
      status == TransactionsStatus.loading ||
      status == TransactionsStatus.loadingMore ||
      status == TransactionsStatus.refreshing;

  TransactionsState copyWith({
    TransactionsStatus? status,
    List<Transaction>? transactions,
    Pagination? pagination,
    String? errorMessage,
    String? loadMoreErrorMessage,
    String? refreshErrorMessage,
    bool clearError = false,
    bool clearLoadMoreError = false,
    bool clearRefreshError = false,
    bool clearTransactions = false,
  }) {
    return TransactionsState(
      status: status ?? this.status,
      transactions: clearTransactions
          ? const <Transaction>[]
          : (transactions ?? this.transactions),
      pagination: pagination ?? this.pagination,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      loadMoreErrorMessage: clearLoadMoreError
          ? null
          : (loadMoreErrorMessage ?? this.loadMoreErrorMessage),
      refreshErrorMessage: clearRefreshError
          ? null
          : (refreshErrorMessage ?? this.refreshErrorMessage),
    );
  }

  @override
  String toString() =>
      'TransactionsState(${status.name}, ${transactions.length} transactions, '
      'page $currentPage)';
}
