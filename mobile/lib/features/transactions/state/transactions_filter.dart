import '../../../models/transaction.dart';

/// The selectable filters above My Purchases.
///
/// The server accepts exactly three lifecycle values — `pending`, `completed`
/// and `cancelled` — and [all] means "send no status". The design's screenshot
/// also shows a separate **Pending** chip, but the backend has no state
/// distinct from `pending`: it is the same record set. Rather than show two
/// chips that cannot produce different results, the row matches the backend's
/// three real states and the app's established label for `pending` — Ongoing
/// (`mobile/DESIGN.md` §26). See the completion report's filter-mapping note.
///
/// The mapping below is the accurate one:
///
///  * [all] → no `status` query parameter.
///  * [ongoing] → `pending` (the app's established label for it).
///  * [completed] → `completed`.
///  * [cancelled] → `cancelled`.
enum TransactionsFilter {
  all('All', null),
  ongoing('Ongoing', TransactionStatus.pending),
  completed('Completed', TransactionStatus.completed),
  cancelled('Cancelled', TransactionStatus.cancelled);

  const TransactionsFilter(this.label, this.status);

  /// The chip label, and the empty-state noun.
  final String label;

  /// The status query this filter sends, or `null` for "everything".
  final TransactionStatus? status;
}
