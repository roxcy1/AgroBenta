import 'dart:async';

import 'package:agrobenta_mobile/features/transactions/state/transactions_controller.dart';
import 'package:agrobenta_mobile/features/transactions/state/transactions_state.dart';
import 'package:agrobenta_mobile/models/transaction.dart';
import 'package:agrobenta_mobile/repositories/transaction_repository.dart';
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
  ({TransactionsController controller, List<TransactionsState> states}) build(
    Future<http.Response> Function(RecordedRequest request) handler, {
    TransactionStatus? status = TransactionStatus.pending,
    TransactionRole? role,
  }) {
    final TransactionsController controller = buildTransactionsController(
      tokenStore,
      handler,
      status: status,
      role: role,
      recorded: recorded,
    );
    addTearDown(controller.dispose);

    final List<TransactionsState> states = <TransactionsState>[
      controller.state,
    ];
    controller.addListener(() => states.add(controller.state));

    return (controller: controller, states: states);
  }

  group('initial load', () {
    test('starts in the initial state with nothing to show', () {
      final TransactionsController controller = buildTransactionsController(
        tokenStore,
        (_) async => transactionListResponse(),
      );
      addTearDown(controller.dispose);

      expect(controller.state.status, TransactionsStatus.initial);
      expect(controller.state.transactions, isEmpty);
      expect(controller.state.pagination, isNull);
      expect(controller.state.errorMessage, isNull);
    });

    test(
      'loads page one as a status-filtered query and publishes it',
      () async {
        final (:controller, :states) = build(
          (_) async => transactionListResponse(
            transactions: <Map<String, dynamic>>[
              transactionJson(id: 5),
              transactionJson(id: 4),
            ],
            total: 2,
          ),
        );

        await controller.loadInitial();

        expect(controller.state.status, TransactionsStatus.ready);
        expect(controller.state.transactions, hasLength(2));
        expect(controller.state.isEmpty, isFalse);
        expect(
          states.map((TransactionsState s) => s.status),
          containsAllInOrder(<TransactionsStatus>[
            TransactionsStatus.loading,
            TransactionsStatus.ready,
          ]),
        );

        expect(recorded, hasLength(1));
        final RecordedRequest request = recorded.single;
        expect(request.method, 'GET');
        expect(request.apiPath, '/transactions');
        expect(
          request.query['status'],
          'pending',
          reason: 'each filter is an independent filtered query',
        );
        expect(request.query['page'], '1');
        expect(
          request.query['per_page'],
          '15',
          reason: 'the repository sends the default page size explicitly',
        );
        expect(
          request.query.containsKey('role'),
          isFalse,
          reason:
              'the tab shows both sides of the caller unless asked otherwise',
        );
      },
    );

    test('a completed tab queries the completed state', () async {
      final (:controller, :states) = build(
        (_) async => transactionListResponse(),
        status: TransactionStatus.completed,
      );

      await controller.loadInitial();

      expect(controller.state.status, TransactionsStatus.ready);
      expect(states, isNotEmpty);
      expect(recorded.single.query['status'], 'completed');
    });

    test('the All filter sends the buyer role and no status', () async {
      final (:controller, :states) = build(
        (_) async => transactionListResponse(),
        status: null,
        role: TransactionRole.buyer,
      );

      await controller.loadInitial();

      expect(controller.state.status, TransactionsStatus.ready);
      final RecordedRequest request = recorded.single;
      expect(request.query['role'], 'buyer');
      expect(
        request.query.containsKey('status'),
        isFalse,
        reason: 'All means the server returns every status',
      );
      expect(
        request.query.keys,
        containsAll(<String>{'role', 'page', 'per_page'}),
      );
    });

    test('keeps the buyer role on later pages and refresh', () async {
      final (:controller, :states) = build(
        (RecordedRequest request) async {
          final int page = int.parse(request.query['page'] ?? '1');
          return transactionListResponse(
            transactions: <Map<String, dynamic>>[
              transactionJson(id: page == 1 ? 3 : 2),
            ],
            currentPage: page,
            lastPage: 2,
            total: 2,
          );
        },
        status: null,
        role: TransactionRole.buyer,
      );

      await controller.loadInitial();
      await controller.loadMore();
      await controller.refresh();

      expect(recorded, hasLength(3));
      for (final RecordedRequest request in recorded) {
        expect(request.query['role'], 'buyer');
        expect(request.query.containsKey('status'), isFalse);
      }
    });

    test(
      'does not send a second request when called twice back to back',
      () async {
        final (:controller, :states) = build(
          (_) async => transactionListResponse(),
        );

        final Future<void> first = controller.loadInitial();
        final Future<void> second = controller.loadInitial();
        await Future.wait<void>(<Future<void>>[first, second]);

        expect(recorded, hasLength(1));
      },
    );
  });

  group('empty results', () {
    test('distinguishes an empty tab from a failed request', () async {
      final (:controller, :states) = build(
        (_) async => transactionListResponse(
          transactions: <Map<String, dynamic>>[],
          total: 0,
        ),
      );

      await controller.loadInitial();

      expect(controller.state.status, TransactionsStatus.ready);
      expect(controller.state.transactions, isEmpty);
      expect(controller.state.isEmpty, isTrue);
      expect(controller.state.errorMessage, isNull);
    });
  });

  group('failures', () {
    test('reports a first-page failure with the server message', () async {
      final (:controller, :states) = build(
        (_) async => transactionServerErrorResponse(),
      );

      await controller.loadInitial();

      expect(controller.state.status, TransactionsStatus.failed);
      expect(controller.state.errorMessage, 'Something went wrong on the server.');
      expect(controller.state.transactions, isEmpty);
    });

    test('falls back to fixed wording when the server sends none', () async {
      final (:controller, :states) = build((_) async => http.Response('', 500));

      await controller.loadInitial();

      expect(controller.state.status, TransactionsStatus.failed);
      expect(
        controller.state.errorMessage,
        'Something went wrong on the server.',
      );
    });
  });

  group('pagination', () {
    test('appends the next page and advances the cursor', () async {
      final (:controller, :states) = build((RecordedRequest request) async {
        final int page = int.parse(request.query['page'] ?? '1');
        return transactionListResponse(
          transactions: <Map<String, dynamic>>[
            transactionJson(id: page == 1 ? 3 : 2),
          ],
          currentPage: page,
          lastPage: 2,
          total: 2,
        );
      });

      await controller.loadInitial();
      await controller.loadMore();

      expect(controller.state.status, TransactionsStatus.ready);
      expect(
        controller.state.transactions
            .map((Transaction t) => t.id)
            .toList(growable: false),
        <int>[3, 2],
        reason: 'page two appends to page one in server order',
      );
      expect(controller.state.currentPage, 2);
      expect(recorded, hasLength(2));
      expect(recorded.last.query['page'], '2');
      expect(recorded.last.query['status'], 'pending');
    });

    test('does not request a page the server does not have', () async {
      final (:controller, :states) = build(
        (_) async => transactionListResponse(lastPage: 1, total: 1),
      );

      await controller.loadInitial();
      await controller.loadMore();

      expect(recorded, hasLength(1));
    });

    test('ignores loadMore before the first page is ready', () async {
      final (:controller, :states) = build(
        (_) async => transactionListResponse(),
      );

      await controller.loadMore();

      expect(recorded, isEmpty);
      expect(controller.state.status, TransactionsStatus.initial);
    });

    test('keeps the loaded records when a later page fails', () async {
      final (:controller, :states) = build((RecordedRequest request) async {
        if (request.query['page'] == '2') {
          return transactionServerErrorResponse();
        }
        return transactionListResponse(
          transactions: <Map<String, dynamic>>[transactionJson(id: 3)],
          lastPage: 2,
          total: 2,
        );
      });

      await controller.loadInitial();
      await controller.loadMore();

      expect(controller.state.status, TransactionsStatus.ready);
      expect(controller.state.transactions, hasLength(1));
      expect(controller.state.loadMoreErrorMessage, 'Something went wrong on the server.');
    });
  });

  group('pull to refresh', () {
    test('keeps results on screen while re-querying page one', () async {
      int calls = 0;
      final (:controller, :states) = build((_) async {
        calls++;
        return transactionListResponse(
          transactions: <Map<String, dynamic>>[
            transactionJson(id: calls == 1 ? 3 : 9),
          ],
          total: 1,
        );
      });

      await controller.loadInitial();
      expect(controller.state.transactions.single.id, 3);

      await controller.refresh();

      expect(controller.state.status, TransactionsStatus.ready);
      expect(
        states.map((TransactionsState s) => s.status),
        contains(TransactionsStatus.refreshing),
      );
      expect(controller.state.transactions.single.id, 9);
      expect(recorded.last.query['page'], '1');
    });

    test('reports a refresh failure without dropping the results', () async {
      int calls = 0;
      final (:controller, :states) = build((_) async {
        calls++;
        if (calls == 1) {
          return transactionListResponse(
            transactions: <Map<String, dynamic>>[transactionJson(id: 3)],
          );
        }
        return transactionServerErrorResponse();
      });

      await controller.loadInitial();
      await controller.refresh();

      expect(controller.state.status, TransactionsStatus.ready);
      expect(controller.state.transactions, hasLength(1));
      expect(controller.state.refreshErrorMessage, 'Something went wrong on the server.');
    });
  });

  group('repository policy', () {
    /// The clamping and allow-list live below the controller, so they are
    /// asserted against the repository directly.
    TransactionRepository repository() => buildTransactionRepository(
      tokenStore,
      (_) async => transactionListResponse(),
      recorded: recorded,
    );

    test('clamps per_page to the server maximum', () async {
      await repository().list(perPage: 999);

      expect(recorded.single.query['per_page'], '50');
    });

    test('clamps a per_page below one to one', () async {
      await repository().list(perPage: 0);

      expect(recorded.single.query['per_page'], '1');
    });

    test('normalises a page below one to page one', () async {
      await repository().list(page: 0);

      expect(recorded.single.query['page'], '1');
    });

    test('sends the role selector when one is asked for', () async {
      await repository().list(role: TransactionRole.buyer);

      expect(recorded.single.query['role'], 'buyer');
      expect(
        recorded.single.query.keys,
        containsAll(<String>{'role', 'page', 'per_page'}),
      );
      expect(recorded.single.query.containsKey('status'), isFalse);
    });
  });

  group('lifecycle', () {
    test('does not publish after dispose', () async {
      final Completer<http.Response> completer = Completer<http.Response>();
      final TransactionsController controller = buildTransactionsController(
        tokenStore,
        (_) => completer.future,
      );

      unawaited(controller.loadInitial());
      await pumpEventQueue();

      controller.dispose();
      completer.complete(transactionListResponse());
      await pumpEventQueue();

      expect(controller.state.status, TransactionsStatus.loading);
    });
  });
}
