import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../models/transaction_receipt.dart';
import '../../../repositories/transaction_repository.dart';
import 'transaction_receipt_state.dart';

/// Presentation logic for one completed transaction's receipt.
///
/// Per-screen: the receipt is immutable, so this controller only fetches and
/// exposes it. [load] is idempotent and re-entrant-safe. A `404` (missing or
/// not a party) and a `409` (not completed) both mean "no receipt to show";
/// everything else is a retryable failure.
class TransactionReceiptController extends ChangeNotifier {
  TransactionReceiptController(this._repository, this.transactionId);

  final TransactionRepository _repository;
  final int transactionId;

  TransactionReceiptState _state = const TransactionReceiptState();
  TransactionReceiptState get state => _state;

  bool _disposed = false;
  bool _inFlight = false;

  /// Fetches the receipt from `GET /transactions/{id}/receipt`.
  Future<void> load() async {
    if (_inFlight) {
      return;
    }

    _inFlight = true;
    _set(const TransactionReceiptState(status: TransactionReceiptStatus.loading));

    try {
      final TransactionReceipt receipt = await _repository.receipt(
        transactionId,
      );
      if (_disposed) {
        return;
      }
      _set(
        TransactionReceiptState(
          status: TransactionReceiptStatus.ready,
          receipt: receipt,
        ),
      );
    } on ApiException catch (error) {
      if (_disposed) {
        return;
      }
      if (error.kind == ApiErrorKind.notFound ||
          error.kind == ApiErrorKind.conflict) {
        _set(
          const TransactionReceiptState(
            status: TransactionReceiptStatus.unavailable,
          ),
        );
        return;
      }
      _set(
        TransactionReceiptState(
          status: TransactionReceiptStatus.failed,
          errorMessage: error.message,
        ),
      );
    } on Object {
      if (_disposed) {
        return;
      }
      _set(
        const TransactionReceiptState(
          status: TransactionReceiptStatus.failed,
          errorMessage: 'Something went wrong. Please try again.',
        ),
      );
    } finally {
      _inFlight = false;
    }
  }

  void _set(TransactionReceiptState next) {
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
