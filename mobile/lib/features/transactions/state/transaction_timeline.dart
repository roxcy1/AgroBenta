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

/// The honest progress tracker for a purchase or sale.
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
/// Buyer and seller see the same state machine from opposite sides: a buyer
/// submitted a purchase request, while the seller received a sale. The words
/// follow the viewer's server-reported role so neither side is told a story
/// that is false for them.
///
/// `TransactionStatus` has exactly three values and [TransactionStatus.fromValue]
/// throws on anything else, so this switch is exhaustive and cannot silently
/// drop a future status.
abstract final class TransactionTimeline {
  /// The collection-specific fulfillment tracker.
  ///
  /// Pickup and buyer-arranged transportation use
  /// Confirmed → Preparing → Ready for Pickup → Picked Up → Completed.
  /// Seller-arranged delivery uses
  /// Confirmed → Preparing → On the Way → Delivered → Completed.
  ///
  /// Cancelled records keep the existing terminal three-marker outcome so a
  /// cancelled sale never renders a completion as reached.
  static List<TimelineStep> fulfillmentStepsFor(Transaction transaction) {
    if (transaction.status == TransactionStatus.cancelled) {
      return stepsFor(transaction.status, role: transaction.role);
    }

    // An unknown non-null stage is not evidence of Confirmed. The screens show
    // an explicit unavailable state and do not call this method for it.
    if (transaction.hasUnknownFulfillmentStatus) {
      return const <TimelineStep>[];
    }

    final TransactionFulfillmentStatus? current =
        transaction.effectiveFulfillmentStatus;
    if (current == null) {
      return stepsFor(transaction.status, role: transaction.role);
    }

    final bool isSeller = transaction.role == TransactionRole.seller;
    final bool isDelivery = transaction.terms.isDelivery;
    final List<TransactionFulfillmentStatus> stages = isDelivery
        ? const <TransactionFulfillmentStatus>[
            TransactionFulfillmentStatus.confirmed,
            TransactionFulfillmentStatus.preparing,
            TransactionFulfillmentStatus.onTheWay,
            TransactionFulfillmentStatus.delivered,
            TransactionFulfillmentStatus.completed,
          ]
        : const <TransactionFulfillmentStatus>[
            TransactionFulfillmentStatus.confirmed,
            TransactionFulfillmentStatus.preparing,
            TransactionFulfillmentStatus.readyForPickup,
            TransactionFulfillmentStatus.pickedUp,
            TransactionFulfillmentStatus.completed,
          ];

    final int currentIndex = stages.indexOf(current);

    return <TimelineStep>[
      for (int i = 0; i < stages.length; i++)
        TimelineStep(
          title: stages[i].label,
          detail: _fulfillmentDetail(stages[i], isSeller: isSeller),
          state: i < currentIndex
              ? TimelineStepState.completed
              : i == currentIndex
              ? TimelineStepState.current
              : TimelineStepState.upcoming,
        ),
    ];
  }

  static String _fulfillmentDetail(
    TransactionFulfillmentStatus stage, {
    required bool isSeller,
  }) {
    return switch (stage) {
      TransactionFulfillmentStatus.confirmed =>
        isSeller
            ? 'The sale is confirmed and the livestock is reserved.'
            : 'Your purchase is confirmed and the livestock is reserved.',
      TransactionFulfillmentStatus.preparing =>
        isSeller
            ? 'Prepare the livestock for pickup or delivery.'
            : 'The seller is preparing the livestock.',
      TransactionFulfillmentStatus.readyForPickup =>
        isSeller
            ? 'Marked ready for pickup. Confirm handover when the buyer collects it.'
            : 'The livestock is ready. Arrange the handover with the seller.',
      TransactionFulfillmentStatus.pickedUp =>
        isSeller
            ? 'Handover reported. Waiting for the buyer to confirm receipt.'
            : 'The seller reported the handover. Confirm receipt when you have the livestock.',
      TransactionFulfillmentStatus.onTheWay =>
        isSeller
            ? 'The livestock is on the way to the buyer.'
            : 'The seller has dispatched the livestock.',
      TransactionFulfillmentStatus.delivered =>
        isSeller
            ? 'Delivery reported. Waiting for the buyer to confirm receipt.'
            : 'The seller reported delivery. Confirm receipt when you have the livestock.',
      TransactionFulfillmentStatus.completed =>
        isSeller
            ? 'The buyer confirmed receipt. This sale is complete.'
            : 'You confirmed receipt. This sale is complete.',
    };
  }

  static List<TimelineStep> stepsFor(
    TransactionStatus status, {
    TransactionRole role = TransactionRole.buyer,
  }) {
    final bool isSeller = role == TransactionRole.seller;

    return switch (status) {
      TransactionStatus.pending => <TimelineStep>[
        TimelineStep(
          title: isSeller ? 'Sale recorded' : 'Purchase request submitted',
          detail: isSeller
              ? 'A buyer requested this listing. This is not yet a confirmed '
                    'sale.'
              : 'Your request was sent to the seller. This is not yet a '
                    'confirmed sale.',
          state: TimelineStepState.completed,
        ),
        TimelineStep(
          title: 'In progress',
          detail: isSeller
              ? 'This sale has not been completed yet. Either party can still '
                    'cancel it.'
              : 'The seller has not accepted or completed this request yet. '
                    'Either party can still cancel it.',
          state: TimelineStepState.current,
        ),
        TimelineStep(
          title: 'Outcome',
          detail: isSeller
              ? 'A sale can end as completed or cancelled. No outcome has been '
                    'recorded yet.'
              : 'A request can end as completed or cancelled. No outcome has '
                    'been recorded yet.',
          state: TimelineStepState.upcoming,
        ),
      ],
      TransactionStatus.completed => <TimelineStep>[
        TimelineStep(
          title: isSeller ? 'Sale recorded' : 'Purchase request submitted',
          detail: isSeller
              ? 'A buyer requested this listing.'
              : 'Your request was sent to the seller.',
          state: TimelineStepState.completed,
        ),
        TimelineStep(
          title: 'In progress',
          detail: isSeller
              ? 'The sale was open and is no longer pending.'
              : 'The request was open and is no longer pending.',
          state: TimelineStepState.completed,
        ),
        const TimelineStep(
          title: 'Completed',
          detail: 'This sale is recorded as complete and cannot change.',
          state: TimelineStepState.current,
        ),
      ],
      TransactionStatus.cancelled => <TimelineStep>[
        TimelineStep(
          title: isSeller ? 'Sale recorded' : 'Purchase request submitted',
          detail: isSeller
              ? 'A buyer requested this listing.'
              : 'Your request was sent to the seller.',
          state: TimelineStepState.completed,
        ),
        TimelineStep(
          title: 'Cancelled',
          detail: isSeller
              ? 'This sale was cancelled and cannot change. It was not '
                    'completed.'
              : 'This request was cancelled and cannot change. It was not '
                    'completed.',
          state: TimelineStepState.current,
        ),
        TimelineStep(
          title: 'Completion',
          detail: isSeller
              ? 'A cancelled sale is never completed.'
              : 'A cancelled request is never completed.',
          state: TimelineStepState.unreached,
        ),
      ],
    };
  }
}
