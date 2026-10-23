import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../models/transaction.dart';
import '../../../models/transaction_page.dart';
import '../../../repositories/transaction_repository.dart';
import 'transactions_state.dart';

/// Presentation logic for one purchases filter.
///
/// One instance per filter. Each filter is an independent filtered query with
/// its own pages; `null` [status] is the "All" filter and sends no status.
/// [role] narrows to one side of the caller's records — My Purchases passes
/// `buyer` so a sale can never appear among a user's purchases. The screen
/// owns the instances and disposes them.
///
/// The mechanics mirror `MarketplaceController`: generation-guarded first
/// pages, a `loadMore` guard, and a `refresh` that keeps results on screen.
/// The differences are ruled by the lifecycle: there is no search, no filter,
/// and no re-sort — the server order is the order.
class TransactionsController extends ChangeNotifier {
  TransactionsController(this._repository, this.status, {this.role});

  final TransactionRepository _repository;

  /// The lifecycle state this filter shows; `null` means all of them.
  /// Fixed for the controller's life.
  final TransactionStatus? status;

  /// The side of the caller's records to show; `null` means both.
  final TransactionRole? role;

  TransactionsState _state = const TransactionsState();
  TransactionsState get state => _state;

  bool _disposed = false;
  bool _loadingMore = false;
  int _generation = 0;

  /// Loads the first page, unless one is already in flight.
  Future<void> loadInitial() {
    if (_state.status == TransactionsStatus.loading ||
        _state.status == TransactionsStatus.refreshing) {
      return Future<void>.value();
    }
    return _loadFirstPage();
  }

  /// Requests the next page, if the server has one and none is in flight.
  Future<void> loadMore() async {
    if (_loadingMore || !_state.hasMorePages) {
      return;
    }
    if (_state.status != TransactionsStatus.ready) {
      return;
    }

    _loadingMore = true;
    _set(
      _state.copyWith(
        status: TransactionsStatus.loadingMore,
        clearLoadMoreError: true,
      ),
    );

    try {
      final TransactionPage page = await _repository.list(
        role: role,
        status: status,
        page: _state.currentPage + 1,
      );
      if (_disposed) {
        return;
      }
      _set(
        _state.copyWith(
          status: TransactionsStatus.ready,
          transactions: <Transaction>[
            ..._state.transactions,
            ...page.transactions,
          ],
          pagination: page.pagination,
        ),
      );
    } on ApiException catch (error) {
      if (_disposed) {
        return;
      }
      _set(
        _state.copyWith(
          status: TransactionsStatus.ready,
          loadMoreErrorMessage: error.message,
        ),
      );
    } on Object {
      if (_disposed) {
        return;
      }
      _set(
        _state.copyWith(
          status: TransactionsStatus.ready,
          loadMoreErrorMessage: 'Something went wrong. Please try again.',
        ),
      );
    } finally {
      _loadingMore = false;
    }
  }

  /// Re-queries page 1 while keeping what is on screen.
  Future<void> refresh() => _loadFirstPage(keepResults: true);

  Future<void> _loadFirstPage({bool keepResults = false}) async {
    final int generation = ++_generation;

    _set(
      _state.copyWith(
        status: keepResults
            ? TransactionsStatus.refreshing
            : TransactionsStatus.loading,
        clearTransactions: !keepResults,
        clearError: true,
        clearLoadMoreError: true,
        clearRefreshError: true,
      ),
    );

    try {
      final TransactionPage page = await _repository.list(
        role: role,
        status: status,
        page: 1,
      );
      if (_disposed || generation != _generation) {
        return;
      }
      _set(
        _state.copyWith(
          status: TransactionsStatus.ready,
          transactions: page.transactions,
          pagination: page.pagination,
        ),
      );
    } on ApiException catch (error) {
      if (_disposed || generation != _generation) {
        return;
      }
      _set(
        keepResults
            ? _state.copyWith(
                status: TransactionsStatus.ready,
                refreshErrorMessage: error.message,
              )
            : _state.copyWith(
                status: TransactionsStatus.failed,
                errorMessage: error.message,
              ),
      );
    } on Object {
      if (_disposed || generation != _generation) {
        return;
      }
      const String message = 'Something went wrong. Please try again.';
      _set(
        keepResults
            ? _state.copyWith(
                status: TransactionsStatus.ready,
                refreshErrorMessage: message,
              )
            : _state.copyWith(
                status: TransactionsStatus.failed,
                errorMessage: message,
              ),
      );
    }
  }

  void _set(TransactionsState next) {
    if (_disposed) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
