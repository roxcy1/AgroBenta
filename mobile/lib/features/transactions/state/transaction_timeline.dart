import '../../../models/transaction.dart';

/// The state of one marker on the transaction progress tracker.
enum TimelineStepState {
  /// This step is behind the record's current position.
  completed,

  /// The record's current position.
  current,

  /// Not reached yet.
  upcoming,

  /// A terminal exit that did not happen: the record was cancelled, so this
  /// step will never be reached. Never rendered as "completed".
  unreached,
}

/// One marker on the progress tracker, derived only from the record's real
/// current status.
///
/// Deliberately carries **no timestamp**: `MobileTransactionResource` returns
/// a single `status` plus the record's `created_at`/`updated_at`, and the
/// backend keeps no per-step history (`transactions` has no history table —
/// migration `2026_09_20_120004_create_transactions_table`). A date per step
/// would be invented, so none is modelled.
class TimelineStep {
  const TimelineStep({
    required this.title,
    required this.detail,
    required this.state,
  });

  final String title;
  final String detail;
  final TimelineStepState state;
}

/// The honest progress tracker for a purchase request.
///
/// The backend workflow is a single `pending` state with two terminal exits,
/// `completed` and `cancelled` [D-15]. There is no seller-acceptance step, no
/// delivery step and no receipt step in the data model, and no transition
/// history, so those screenshot steps are **not** produced here. What is
/// produced is the real, three-marker shape of the state machine:
///
///  * Submitted  — always complete once a record exists;
///  * In progress — `current` while `pending`, complete once terminal;
///  * Outcome     — current for `completed`, an `unreached` dead end for
///                  `cancelled`, and `upcoming` (with an honest, non-promising
///                  label) while still `pending`.
///
/// `TransactionStatus` has exactly three values and [TransactionStatus.fromValue]
/// throws on anything else, so this switch is exhaustive and cannot silently
/// drop a future status.
abstract final class TransactionTimeline {
  static List<TimelineStep> stepsFor(TransactionStatus status) {
    return switch (status) {
      TransactionStatus.pending => const <TimelineStep>[
        TimelineStep(
          title: 'Purchase request submitted',
          detail:
              'Your request was sent to the seller. This is not yet a '
              'confirmed sale.',
          state: TimelineStepState.completed,
        ),
        TimelineStep(
          title: 'In progress',
          detail:
              'The seller has not accepted or completed this request yet. '
              'Either party can still cancel it.',
          state: TimelineStepState.current,
        ),
        TimelineStep(
          title: 'Outcome',
          detail:
              'A request can end as completed or cancelled. No outcome has '
              'been recorded yet.',
          state: TimelineStepState.upcoming,
        ),
      ],
      TransactionStatus.completed => const <TimelineStep>[
        TimelineStep(
          title: 'Purchase request submitted',
          detail: 'Your request was sent to the seller.',
          state: TimelineStepState.completed,
        ),
        TimelineStep(
          title: 'In progress',
          detail: 'The request was open and is no longer pending.',
          state: TimelineStepState.completed,
        ),
        TimelineStep(
          title: 'Completed',
          detail: 'This sale is recorded as complete and cannot change.',
          state: TimelineStepState.current,
        ),
      ],
      TransactionStatus.cancelled => const <TimelineStep>[
        TimelineStep(
          title: 'Purchase request submitted',
          detail: 'Your request was sent to the seller.',
          state: TimelineStepState.completed,
        ),
        TimelineStep(
          title: 'Cancelled',
          detail:
              'This request was cancelled and cannot change. It was not '
              'completed.',
          state: TimelineStepState.current,
        ),
        TimelineStep(
          title: 'Completion',
          detail: 'A cancelled request is never completed.',
          state: TimelineStepState.unreached,
        ),
      ],
    };
  }
}
