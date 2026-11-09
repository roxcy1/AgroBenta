import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../models/transaction.dart';
import '../../../repositories/transaction_repository.dart';
import 'transaction_detail_state.dart';

/// Presentation logic for one transaction's detail screen.
///
/// Scoped to a single transaction: the screen owns an instance and disposes
/// it. [load] is idempotent and re-entrant-safe; [cancel] and
/// [performAction] guard on the server-permitted actions and keep the loaded
/// record on screen while in flight.
class TransactionDetailController extends ChangeNotifier {
  TransactionDetailController(this._repository, this.transactionId);

  final TransactionRepository _repository;
  final int transactionId;

  TransactionDetailState _state = const TransactionDetailState();
  TransactionDetailState get state => _state;

  bool _disposed = false;
  bool _inFlight = false;
  bool _cancelling = false;
  bool _actionInFlight = false;

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
        _set(
          const TransactionDetailState(
            status: TransactionDetailStatus.unavailable,
          ),
        );
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
    if (_cancelling ||
        _actionInFlight ||
        current == null ||
        !current.canCancel) {
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

  /// Performs one server-permitted fulfillment action.
  ///
  /// The action is re-checked against the loaded record's `permitted_actions`
  /// so a stale button cannot send a request the server no longer allows. The
  /// updated record returned by the server replaces the current one, which is
  /// what refreshes the available next action.
  Future<bool> performAction(TransactionFulfillmentAction action) async {
    final Transaction? current = _state.transaction;
    if (_actionInFlight ||
        _cancelling ||
        current == null ||
        !current.permits(action.value)) {
      return false;
    }

    _actionInFlight = true;
    _set(
      TransactionDetailState(
        status: TransactionDetailStatus.updating,
        transaction: current,
        activeAction: action,
      ),
    );

    try {
      final Transaction updated = await _repository.performFulfillmentAction(
        transactionId,
        action,
      );
      if (_disposed) {
        return false;
      }
      _set(
        TransactionDetailState(
          status: TransactionDetailStatus.ready,
          transaction: updated,
        ),
      );
      return true;
    } on ApiException catch (error) {
      if (_disposed) {
        return false;
      }

      // A 409 means another party changed the record or the stage is stale.
      // Reload first, then surface a notice beside the authoritative state.
      if (error.kind == ApiErrorKind.conflict) {
        await load();
        _showActionNotice(
          'This transaction changed. The latest state is shown.',
        );
        return false;
      }

      if (error.kind == ApiErrorKind.notFound) {
        await load();
        return false;
      }

      _set(
        TransactionDetailState(
          status: TransactionDetailStatus.ready,
          transaction: current,
          actionErrorMessage: error.message,
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
          actionErrorMessage: 'Something went wrong. Please try again.',
        ),
      );
      return false;
    } finally {
      _actionInFlight = false;
    }
  }

  /// Discards the fulfillment-action notice after it has been shown.
  void clearActionError() {
    final Transaction? current = _state.transaction;
    if (_state.actionErrorMessage == null || current == null) {
      return;
    }
    _set(
      TransactionDetailState(
        status: TransactionDetailStatus.ready,
        transaction: current,
      ),
    );
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

  /// Shows a notice over the current ready record after a conflicting action.
  void _showActionNotice(String message) {
    final Transaction? current = _state.transaction;
    if (_disposed || current == null) {
      return;
    }
    _set(
      TransactionDetailState(
        status: TransactionDetailStatus.ready,
        transaction: current,
        actionErrorMessage: message,
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
