import '../../../models/transaction.dart';

/// Where one transaction's detail request is in its lifecycle.
enum TransactionDetailStatus {
  /// The request has not been made yet.
  initial,

  /// In flight.
  loading,

  /// The transaction is loaded and may be shown.
  ready,

  /// The transaction is not visible to this user (404: missing or not a
  /// party — the server does not distinguish, so neither does the app).
  unavailable,

  /// The request failed for a reason other than "not visible".
  failed,

  /// A cancel call is in flight. The loaded transaction stays on screen.
  cancelling,

  /// A fulfillment action is in flight. The loaded transaction stays on screen.
  updating,
}

/// An immutable snapshot for the transaction detail screen.
///
/// The one rule: a transaction is only ever shown from [ready], which is only
/// ever reached by a successful `GET /transactions/{id}`. The list response
/// is never used as detail content.
class TransactionDetailState {
  const TransactionDetailState({
    this.status = TransactionDetailStatus.initial,
    this.transaction,
    this.errorMessage,
    this.cancelErrorMessage,
    this.actionErrorMessage,
    this.activeAction,
  });

  final TransactionDetailStatus status;

  /// The transaction, set while [status] is `ready` or `cancelling`.
  final Transaction? transaction;

  /// A displayable failure, for [TransactionDetailStatus.failed] only.
  final String? errorMessage;

  /// A displayable failure for a cancel that did not succeed. The loaded
  /// transaction stays on screen; only the notice appears.
  final String? cancelErrorMessage;

  /// A displayable failure or stale-state notice for a fulfillment action.
  final String? actionErrorMessage;

  /// The fulfillment action currently in flight, when [status] is `updating`.
  final TransactionFulfillmentAction? activeAction;

  bool get isLoading => status == TransactionDetailStatus.loading;

  bool get isUnavailable => status == TransactionDetailStatus.unavailable;

  bool get isCancelling => status == TransactionDetailStatus.cancelling;

  bool get isUpdating => status == TransactionDetailStatus.updating;

  bool get isBusy => isCancelling || isUpdating;

  /// Cancel is offered only when the server says so. That keeps the client
  /// from offering a cancellation after the handover/dispatch cutoff.
  bool get canCancel =>
      (status == TransactionDetailStatus.ready ||
          status == TransactionDetailStatus.cancelling) &&
      (transaction?.canCancel ?? false) &&
      !(transaction?.hasUnknownFulfillmentStatus ?? false);

  bool get canConfirmReceived =>
      status == TransactionDetailStatus.ready &&
      (transaction?.canConfirmReceived ?? false) &&
      !(transaction?.hasUnknownFulfillmentStatus ?? false);

  TransactionFulfillmentAction? get nextSellerAction =>
      status == TransactionDetailStatus.ready &&
          !(transaction?.hasUnknownFulfillmentStatus ?? false)
      ? transaction?.nextSellerAction
      : null;

  @override
  String toString() => 'TransactionDetailState(${status.name})';
}
