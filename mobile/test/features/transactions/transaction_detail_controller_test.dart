import 'dart:async';

import 'package:agrobenta_mobile/features/transactions/state/transaction_detail_controller.dart';
import 'package:agrobenta_mobile/features/transactions/state/transaction_detail_state.dart';
import 'package:agrobenta_mobile/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/transaction_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  setUp(() {
    tokenStore = FakeTokenStore('token');
    recorded = <RecordedRequest>[];
  });

  /// A controller over a handler, plus a record of every notification.
  ({
    TransactionDetailController controller,
    List<TransactionDetailState> states,
  }) build(
    Future<http.Response> Function(RecordedRequest request) handler, {
    int transactionId = 1,
  }) {
    final TransactionDetailController controller =
        buildTransactionDetailController(
          tokenStore,
          handler,
          transactionId: transactionId,
          recorded: recorded,
        );
    addTearDown(controller.dispose);

    final List<TransactionDetailState> states = <TransactionDetailState>[
      controller.state,
    ];
    controller.addListener(() => states.add(controller.state));

    return (controller: controller, states: states);
  }

  group('load', () {
    test('starts in the initial state with nothing to show', () {
      final TransactionDetailController controller =
          buildTransactionDetailController(
            tokenStore,
            (_) async => transactionDetailResponse(),
          );
      addTearDown(controller.dispose);

      expect(controller.state.status, TransactionDetailStatus.initial);
      expect(controller.state.transaction, isNull);
      expect(controller.state.canCancel, isFalse);
    });

    test('loads one transaction and publishes it', () async {
      final (:controller, :states) = build(
        (_) async => transactionDetailResponse(
          transaction: transactionJson(id: 1, status: 'pending'),
        ),
      );

      await controller.load();

      expect(controller.state.status, TransactionDetailStatus.ready);
      final Transaction transaction = controller.state.transaction!;
      expect(transaction.id, 1);
      expect(transaction.status, TransactionStatus.pending);
      expect(
        controller.state.canCancel,
        isTrue,
        reason: 'cancel is offered while pending, to either party',
      );

      expect(recorded, hasLength(1));
      expect(recorded.single.method, 'GET');
      expect(recorded.single.apiPath, '/transactions/1');
    });

    test('maps a 404 to unavailable rather than a failure', () async {
      final (:controller, :states) = build(
        (_) async => transactionNotFoundResponse(),
      );

      await controller.load();

      expect(controller.state.status, TransactionDetailStatus.unavailable);
      expect(controller.state.isUnavailable, isTrue);
      expect(controller.state.transaction, isNull);
      expect(controller.state.errorMessage, isNull);
    });

    test('maps a server failure to failed with the server message', () async {
      final (:controller, :states) = build(
        (_) async => transactionServerErrorResponse(),
      );

      await controller.load();

      expect(controller.state.status, TransactionDetailStatus.failed);
      expect(controller.state.errorMessage, 'Server error.');
      expect(controller.state.transaction, isNull);
    });

    test('ignores a second load while one is in flight', () async {
      final Completer<http.Response> completer = Completer<http.Response>();
      final (:controller, :states) = build((_) => completer.future);

      final Future<void> first = controller.load();
      final Future<void> second = controller.load();
      await pumpEventQueue();

      completer.complete(
        transactionDetailResponse(transaction: transactionJson(id: 1)),
      );
      await Future.wait<void>(<Future<void>>[first, second]);

      expect(recorded, hasLength(1));
      expect(controller.state.status, TransactionDetailStatus.ready);
    });
  });

  group('cancel', () {
    /// A handler where the record is pending on read and cancelled on cancel.
    Future<http.Response> pendingThenCancelled(RecordedRequest request) async {
      if (request.method == 'POST') {
        return transactionDetailResponse(
          transaction: transactionJson(id: 1, status: 'cancelled'),
        );
      }
      return transactionDetailResponse(
        transaction: transactionJson(id: 1, status: 'pending'),
      );
    }

    test('cancels a pending transaction', () async {
      final (:controller, :states) = build(pendingThenCancelled);
      await controller.load();

      final bool cancelled = await controller.cancel();

      expect(cancelled, isTrue);
      expect(controller.state.status, TransactionDetailStatus.ready);
      expect(controller.state.transaction!.status, TransactionStatus.cancelled);
      expect(controller.state.canCancel, isFalse);
      expect(controller.state.cancelErrorMessage, isNull);
      expect(
        states.map((TransactionDetailState s) => s.status),
        containsAllInOrder(<TransactionDetailStatus>[
          TransactionDetailStatus.loading,
          TransactionDetailStatus.ready,
          TransactionDetailStatus.cancelling,
          TransactionDetailStatus.ready,
        ]),
      );

      expect(recorded, hasLength(2));
      final RecordedRequest post = recorded.last;
      expect(post.method, 'POST');
      expect(post.apiPath, '/transactions/1/cancel');
      expect(post.query, isEmpty, reason: 'the cancel body allow-list is empty');
    });

    test('offers no cancel for a transaction that is not pending', () async {
      final (:controller, :states) = build(
        (_) async => transactionDetailResponse(
          transaction: transactionJson(id: 1, status: 'cancelled'),
        ),
      );
      await controller.load();

      final bool cancelled = await controller.cancel();

      expect(cancelled, isFalse);
      expect(controller.state.canCancel, isFalse);
      expect(
        recorded,
        hasLength(1),
        reason: 'a terminal record must not produce a request at all',
      );
    });

    test('reloads when the record already left pending (409)', () async {
      int gets = 0;
      final (:controller, :states) = build((RecordedRequest request) async {
        if (request.method == 'POST') {
          return transactionConflictResponse();
        }
        gets++;
        // The first read is pending; the reload after the conflict shows the
        // terminal state another party produced.
        return transactionDetailResponse(
          transaction: transactionJson(
            id: 1,
            status: gets == 1 ? 'pending' : 'cancelled',
          ),
        );
      });
      await controller.load();

      final bool cancelled = await controller.cancel();

      expect(cancelled, isFalse);
      expect(controller.state.status, TransactionDetailStatus.ready);
      expect(controller.state.transaction!.status, TransactionStatus.cancelled);
      expect(controller.state.cancelErrorMessage, isNull);
      expect(controller.state.canCancel, isFalse);
      expect(
        gets,
        2,
        reason: 'a conflict re-fetches so the screen shows the real state',
      );
    });

    test('keeps the record and surfaces the message when cancel fails', () async {
      final (:controller, :states) = build((RecordedRequest request) async {
        if (request.method == 'POST') {
          return transactionServerErrorResponse();
        }
        return transactionDetailResponse(
          transaction: transactionJson(id: 1, status: 'pending'),
        );
      });
      await controller.load();

      final bool cancelled = await controller.cancel();

      expect(cancelled, isFalse);
      expect(controller.state.status, TransactionDetailStatus.ready);
      expect(controller.state.transaction!.status, TransactionStatus.pending);
      expect(controller.state.cancelErrorMessage, 'Server error.');
      expect(controller.state.canCancel, isTrue);
    });

    test('clearCancelError drops the notice and nothing else', () async {
      final (:controller, :states) = build((RecordedRequest request) async {
        if (request.method == 'POST') {
          return transactionServerErrorResponse();
        }
        return transactionDetailResponse(
          transaction: transactionJson(id: 1, status: 'pending'),
        );
      });
      await controller.load();
      await controller.cancel();
      expect(controller.state.cancelErrorMessage, isNotNull);

      controller.clearCancelError();

      expect(controller.state.cancelErrorMessage, isNull);
      expect(controller.state.status, TransactionDetailStatus.ready);
      expect(controller.state.transaction!.id, 1);
      expect(controller.state.canCancel, isTrue);
    });
  });
}
