import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../models/transaction.dart';
import '../../../repositories/transaction_repository.dart';
import 'transaction_detail_state.dart';

/// Presentation logic for one transaction's detail screen.
///
/// Scoped to a single transaction: the screen owns an instance and disposes
/// it. [load] is idempotent and re-entrant-safe; [cancel] guards on the
/// pending state and keeps the loaded record on screen while in flight.
///
/// There is deliberately **no `complete` method**. The backend answers that
/// transition with 501 (OQ-15) and the client hides the affordance entirely.
class TransactionDetailController extends ChangeNotifier {
  TransactionDetailController(this._repository, this.transactionId);

  final TransactionRepository _repository;
  final int transactionId;

  TransactionDetailState _state = const TransactionDetailState();
  TransactionDetailState get state => _state;

  bool _disposed = false;
  bool _inFlight = false;
  bool _cancelling = false;

  /// Fetches the transaction from `GET /transactions/{id}`.
  Future<void> load() async {
    if (_inFlight) {
      return;
    }

    _inFlight = true;
    _set(const TransactionDetailState(status: TransactionDetailStatus.loading));

    try {
      final Transaction transaction = await _repository.detail(transactionId);
      if (_disposed) {
        return;
      }
      _set(
        TransactionDetailState(
          status: TransactionDetailStatus.ready,
          transaction: transaction,
        ),
      );
    } on ApiException catch (error) {
      if (_disposed) {
        return;
      }
      if (error.kind == ApiErrorKind.notFound) {
        _set(const TransactionDetailState(status: TransactionDetailStatus.unavailable));
        return;
      }
      _set(
        TransactionDetailState(
          status: TransactionDetailStatus.failed,
          errorMessage: error.message,
        ),
      );
    } on Object {
      if (_disposed) {
        return;
      }
      _set(
        const TransactionDetailState(
          status: TransactionDetailStatus.failed,
          errorMessage: 'Something went wrong. Please try again.',
        ),
      );
    } finally {
      _inFlight = false;
    }
  }

  /// Cancels a pending transaction. Returns `true` when the record is now
  /// `cancelled`. Either party may cancel ([D-15] rule 5); the transition is
  /// irreversible, so the screen confirms before calling this.
  Future<bool> cancel() async {
    final Transaction? current = _state.transaction;
    if (_cancelling || current == null || !current.isPending) {
      return false;
    }

    _cancelling = true;
    _set(
      TransactionDetailState(
        status: TransactionDetailStatus.cancelling,
        transaction: current,
      ),
    );

    try {
      final Transaction cancelled = await _repository.cancel(transactionId);
      if (_disposed) {
        return false;
      }
      _set(
        TransactionDetailState(
          status: TransactionDetailStatus.ready,
          transaction: cancelled,
        ),
      );
      return true;
    } on ApiException catch (error) {
      if (_disposed) {
        return false;
      }
      // A 409 means the record already left pending elsewhere: reload so the
      // screen shows the terminal state instead of a stale pending one.
      if (error.kind == ApiErrorKind.conflict) {
        await load();
        return false;
      }
      _set(
        TransactionDetailState(
          status: TransactionDetailStatus.ready,
          transaction: current,
          cancelErrorMessage: error.message,
        ),
      );
      return false;
    } on Object {
      if (_disposed) {
        return false;
      }
      _set(
        TransactionDetailState(
          status: TransactionDetailStatus.ready,
          transaction: current,
          cancelErrorMessage: 'Something went wrong. Please try again.',
        ),
      );
      return false;
    } finally {
      _cancelling = false;
    }
  }

  /// Discards the cancel notice after it has been shown.
  void clearCancelError() {
    final Transaction? current = _state.transaction;
    if (_state.cancelErrorMessage == null || current == null) {
      return;
    }
    _set(
      TransactionDetailState(
        status: TransactionDetailStatus.ready,
        transaction: current,
      ),
    );
  }

  void _set(TransactionDetailState next) {
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
