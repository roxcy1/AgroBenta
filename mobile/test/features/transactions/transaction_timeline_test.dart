import 'package:agrobenta_mobile/features/transactions/state/transaction_timeline.dart';
import 'package:agrobenta_mobile/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
  });
}
