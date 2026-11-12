import '../../../models/transaction_receipt.dart';

/// Where one receipt request is in its lifecycle.
enum TransactionReceiptStatus {
  /// The request has not been made yet.
  initial,

  /// In flight.
  loading,

  /// The receipt is loaded and may be shown.
  ready,

  /// The transaction is not visible to this user, or is not completed.
  unavailable,

  /// The request failed for a reason other than "not available".
  failed,
}

/// An immutable snapshot for the receipt screen.
class TransactionReceiptState {
  const TransactionReceiptState({
    this.status = TransactionReceiptStatus.initial,
    this.receipt,
    this.errorMessage,
  });

  final TransactionReceiptStatus status;

  /// The receipt, set while [status] is `ready`.
  final TransactionReceipt? receipt;

  /// A displayable failure, for [TransactionReceiptStatus.failed] only.
  final String? errorMessage;

  bool get isLoading => status == TransactionReceiptStatus.loading;

  bool get isUnavailable => status == TransactionReceiptStatus.unavailable;

  @override
  String toString() => 'TransactionReceiptState(${status.name})';
}
