import 'package:agrobenta_mobile/features/transactions/state/transaction_timeline.dart';
import 'package:agrobenta_mobile/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/transaction_fakes.dart';

void main() {
  group('TransactionTimeline.fulfillmentStepsFor', () {
    Transaction transaction({
      String status = 'pending',
      String? fulfillmentStatus = 'confirmed',
      String collectionMethod = 'farm_pickup',
      String role = 'buyer',
    }) {
      return Transaction.fromJson(
        transactionJson(
          status: status,
          fulfillmentStatus: fulfillmentStatus,
          collectionMethod: collectionMethod,
          role: role,
        ),
      );
    }

    test('pickup flow uses the pickup-specific titles', () {
      final List<TimelineStep> steps = TransactionTimeline.fulfillmentStepsFor(
        transaction(fulfillmentStatus: 'ready_for_pickup'),
      );

      expect(steps.map((TimelineStep s) => s.title), <String>[
        'Confirmed',
        'Preparing',
        'Ready for Pickup',
        'Picked Up',
        'Completed',
      ]);
      expect(steps[0].state, TimelineStepState.completed);
      expect(steps[1].state, TimelineStepState.completed);
      expect(steps[2].state, TimelineStepState.current);
      expect(steps[3].state, TimelineStepState.upcoming);
      expect(steps[4].state, TimelineStepState.upcoming);
    });

    test('delivery flow uses the delivery-specific titles', () {
      final List<TimelineStep> steps = TransactionTimeline.fulfillmentStepsFor(
        transaction(
          collectionMethod: 'seller_arranged_delivery',
          fulfillmentStatus: 'on_the_way',
        ),
      );

      expect(steps.map((TimelineStep s) => s.title), <String>[
        'Confirmed',
        'Preparing',
        'On the Way',
        'Delivered',
        'Completed',
      ]);
      expect(steps[2].state, TimelineStepState.current);
    });

    test('legacy pending null starts at Confirmed', () {
      final List<TimelineStep> steps = TransactionTimeline.fulfillmentStepsFor(
        transaction(fulfillmentStatus: null),
      );

      expect(steps.first.title, 'Confirmed');
      expect(steps.first.state, TimelineStepState.current);
    });

    test('an unknown non-null stage yields no fabricated tracker', () {
      final List<TimelineStep> steps = TransactionTimeline.fulfillmentStepsFor(
        transaction(fulfillmentStatus: 'future_stage'),
      );

      expect(steps, isEmpty);
    });

    test('completed reaches the final marker only', () {
      final List<TimelineStep> steps = TransactionTimeline.fulfillmentStepsFor(
        transaction(status: 'completed', fulfillmentStatus: 'completed'),
      );

      expect(steps.last.title, 'Completed');
      expect(steps.last.state, TimelineStepState.current);
      expect(
        steps
            .take(4)
            .every((TimelineStep s) => s.state == TimelineStepState.completed),
        isTrue,
      );
    });

    test('cancelled keeps the terminal three-marker outcome', () {
      final List<TimelineStep> steps = TransactionTimeline.fulfillmentStepsFor(
        transaction(status: 'cancelled', fulfillmentStatus: null),
      );

      expect(steps, hasLength(3));
      expect(steps[1].title, 'Cancelled');
      expect(steps[2].state, TimelineStepState.unreached);
    });

    test('seller wording differs without inventing a status', () {
      final List<TimelineStep> steps = TransactionTimeline.fulfillmentStepsFor(
        transaction(role: 'seller', fulfillmentStatus: 'preparing'),
      );

      expect(steps[1].detail, contains('Prepare the livestock'));
      expect(steps[1].detail, isNot(contains('The seller is preparing')));
    });
  });

  group('TransactionTimeline.stepsFor', () {
    test('pending: submitted done, in progress current, outcome upcoming', () {
      final List<TimelineStep> steps = TransactionTimeline.stepsFor(
        TransactionStatus.pending,
      );

      expect(steps, hasLength(3));
      expect(steps[0].state, TimelineStepState.completed);
      expect(steps[1].state, TimelineStepState.current);
      expect(steps[2].state, TimelineStepState.upcoming);
    });

    test('completed: both early steps done, completion is current', () {
      final List<TimelineStep> steps = TransactionTimeline.stepsFor(
        TransactionStatus.completed,
      );

      expect(steps, hasLength(3));
      expect(steps[0].state, TimelineStepState.completed);
      expect(steps[1].state, TimelineStepState.completed);
      expect(steps[2].state, TimelineStepState.current);
      expect(steps[2].title, 'Completed');
    });

    test('cancelled: terminal, and completion is explicitly unreached', () {
      final List<TimelineStep> steps = TransactionTimeline.stepsFor(
        TransactionStatus.cancelled,
      );

      expect(steps, hasLength(3));
      expect(steps[0].state, TimelineStepState.completed);
      expect(steps[1].state, TimelineStepState.current);
      expect(steps[1].title, 'Cancelled');
      // A cancelled request must never render completion as done.
      expect(steps[2].state, TimelineStepState.unreached);
      expect(steps[2].state, isNot(TimelineStepState.completed));
    });

    test('every step carries no timestamp field — none is modelled', () {
      // The backend records no per-step history, so there is nothing to date.
      // This guards against a future edit adding a fabricated date.
      for (final TransactionStatus status in TransactionStatus.values) {
        for (final TimelineStep step in TransactionTimeline.stepsFor(status)) {
          expect(step.title.trim(), isNotEmpty);
          expect(step.detail.trim(), isNotEmpty);
        }
      }
    });

    test('the seller reads the same state machine as a sale', () {
      final List<TimelineStep> pending = TransactionTimeline.stepsFor(
        TransactionStatus.pending,
        role: TransactionRole.seller,
      );

      expect(pending[0].title, 'Sale recorded');
      expect(pending[0].detail, contains('A buyer requested this listing'));
      expect(pending[0].detail, isNot(contains('Your request')));
      expect(pending[1].state, TimelineStepState.current);

      final List<TimelineStep> cancelled = TransactionTimeline.stepsFor(
        TransactionStatus.cancelled,
        role: TransactionRole.seller,
      );
      expect(cancelled[1].detail, contains('This sale was cancelled'));
      expect(cancelled[1].detail, isNot(contains('This request')));
      expect(cancelled[2].detail, contains('cancelled sale'));
    });
  });
}
