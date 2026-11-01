import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/transactions/state/transaction_scope.dart';
import 'package:agrobenta_mobile/features/transactions/views/transaction_detail_screen.dart';
import 'package:agrobenta_mobile/features/transactions/views/transactions_screen.dart';
import 'package:agrobenta_mobile/models/transaction.dart';
import 'package:agrobenta_mobile/repositories/transaction_repository.dart';
import 'package:flutter/material.dart';
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

  /// A bounded pump: a `CircularProgressIndicator` schedules frames forever,
  /// so `pumpAndSettle` would never return while a spinner is on screen.
  Future<void> settle(WidgetTester tester, {int frames = 10}) async {
    for (int frame = 0; frame < frames; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    Future<http.Response> Function(RecordedRequest request) handler, {
    Size surface = const Size(800, 1800),
    TransactionRole role = TransactionRole.buyer,
  }) async {
    final TransactionRepository repository = buildTransactionRepository(
      tokenStore,
      handler,
      recorded: recorded,
    );

    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      TransactionScope(
        repository: repository,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: TransactionsScreen(role: role),
        ),
      ),
    );
    await settle(tester);
  }

  List<String> chipLabels(WidgetTester tester) {
    return tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .map((ChoiceChip chip) => (chip.label as Text).data!)
        .toList(growable: false);
  }

  http.Response emptyList() =>
      transactionListResponse(transactions: <Map<String, dynamic>>[], total: 0);

  testWidgets('shows My Purchases and the backend filter chips in order', (
    WidgetTester tester,
  ) async {
    await pumpScreen(tester, (_) async => emptyList());

    expect(find.text('My Purchases'), findsOneWidget);
    expect(chipLabels(tester), <String>[
      'All',
      'Ongoing',
      'Completed',
      'Cancelled',
    ]);

    final ChoiceChip all = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'All'),
    );
    expect(all.selected, isTrue, reason: 'All is the initial filter');
  });

  testWidgets('Seller Mode shows My Sales, queries role=seller and uses sales '
      'empty copy', (WidgetTester tester) async {
    await pumpScreen(
      tester,
      (_) async => emptyList(),
      role: TransactionRole.seller,
    );

    expect(find.text('My Sales'), findsOneWidget);
    expect(find.text('My Purchases'), findsNothing);
    expect(find.text('No sales yet'), findsOneWidget);
    expect(recorded.single.query['role'], 'seller');

    await tester.tap(find.text('Ongoing'));
    await settle(tester);

    expect(find.text('No ongoing sales yet'), findsOneWidget);
    expect(recorded.last.query['role'], 'seller');
    expect(recorded.last.query['status'], 'pending');

    await tester.tap(find.text('Cancelled'));
    await settle(tester);

    expect(find.text('No cancelled sales'), findsOneWidget);
    expect(recorded.last.query['role'], 'seller');
    expect(recorded.last.query['status'], 'cancelled');
  });

  testWidgets('Seller Mode renders a sale from the seller-scoped response', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      (_) async => transactionListResponse(
        transactions: <Map<String, dynamic>>[
          transactionJson(
            id: 11,
            role: 'seller',
            totalAmount: '72000.00',
            counterparty: transactionCounterpartyJson(
              name: 'Ben Cruz',
              email: 'ben@example.test',
            ),
          ),
        ],
        total: 1,
      ),
      role: TransactionRole.seller,
    );

    expect(find.text('My Sales'), findsOneWidget);
    expect(find.text('TRX-011'), findsOneWidget);
    expect(find.text('₱72,000.00'), findsOneWidget);
    expect(recorded.single.query, <String, String>{
      'role': 'seller',
      'page': '1',
      'per_page': '15',
    });
  });

  testWidgets('the design\'s extra Pending chip is omitted because the server '
      'has no state distinct from Ongoing', (WidgetTester tester) async {
    await pumpScreen(tester, (_) async => emptyList());

    expect(
      find.widgetWithText(ChoiceChip, 'Pending'),
      findsNothing,
      reason:
          'a second chip querying the same `pending` status would fabricate a '
          'lifecycle distinction the backend does not persist',
    );
  });

  testWidgets('All queries the buyer role with no status and shows every '
      'record the server returns', (WidgetTester tester) async {
    await pumpScreen(
      tester,
      (_) async => transactionListResponse(
        transactions: <Map<String, dynamic>>[
          transactionJson(id: 7, status: 'pending'),
          transactionJson(id: 8, status: 'completed'),
        ],
        total: 2,
      ),
    );

    expect(recorded, hasLength(1));
    final RecordedRequest request = recorded.single;
    expect(request.method, 'GET');
    expect(request.apiPath, '/transactions');
    expect(request.query['role'], 'buyer');
    expect(request.query.containsKey('status'), isFalse);
    expect(request.query['page'], '1');

    expect(find.text('TRX-007'), findsOneWidget);
    expect(
      find.text('TRX-008'),
      findsOneWidget,
      reason: 'All does not filter client-side or hide a status',
    );
    expect(find.text('Completed'), findsWidgets);
  });

  testWidgets('each working filter queries its verified backend status as the '
      'buyer and is honest when empty', (WidgetTester tester) async {
    await pumpScreen(tester, (_) async => emptyList());

    expect(find.text('No purchases yet'), findsOneWidget);

    await tester.tap(find.text('Ongoing'));
    await settle(tester);

    expect(find.text('No ongoing purchases yet'), findsOneWidget);
    expect(recorded.last.query['role'], 'buyer');
    expect(recorded.last.query['status'], 'pending');

    await tester.tap(find.text('Completed'));
    await settle(tester);

    expect(find.text('No completed purchases yet'), findsOneWidget);
    expect(
      find.text('Completion is not yet available in the app.'),
      findsOneWidget,
      reason:
          'no path in the app can reach completed today (OQ-15); the empty '
          'state says so rather than pretending',
    );
    expect(recorded.last.query['role'], 'buyer');
    expect(recorded.last.query['status'], 'completed');

    await tester.tap(find.text('Cancelled'));
    await settle(tester);

    expect(find.text('No cancelled purchases'), findsOneWidget);
    expect(recorded.last.query['role'], 'buyer');
    expect(recorded.last.query['status'], 'cancelled');
  });

  testWidgets('renders a real record with id, title, agreed price, status and '
      'date', (WidgetTester tester) async {
    await pumpScreen(
      tester,
      (_) async => transactionListResponse(
        transactions: <Map<String, dynamic>>[
          transactionJson(id: 7, totalAmount: '85000.00'),
        ],
        total: 1,
      ),
    );

    expect(find.text('TRX-007'), findsOneWidget);
    expect(find.text('Holstein'), findsOneWidget);
    expect(
      find.text('Agreed price'),
      findsOneWidget,
      reason: 'the amount must not be mistakable for a listing asking price',
    );
    expect(
      find.text('₱85,000.00'),
      findsOneWidget,
      reason: 'the server figure is shown exactly, never computed',
    );
    expect(find.text('Ongoing'), findsWidgets);
    expect(
      find.text('1 Oct 2026'),
      findsOneWidget,
      reason: 'the card date comes from the persisted created_at',
    );
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('long titles and a narrow screen do not overflow', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      (_) async => transactionListResponse(
        transactions: <Map<String, dynamic>>[
          transactionJson(
            id: 7,
            listing: transactionListingJson(
              breed:
                  'A very long breed description that would overflow any '
                  'unbounded horizontal row on a narrow phone',
            ),
          ),
        ],
        total: 1,
      ),
      surface: const Size(320, 900),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a card opens the existing detail screen with the real '
      'id', (WidgetTester tester) async {
    await pumpScreen(tester, (RecordedRequest request) async {
      if (request.apiPath == '/transactions/7') {
        return transactionDetailResponse(transaction: transactionJson(id: 7));
      }
      return transactionListResponse(
        transactions: <Map<String, dynamic>>[
          transactionJson(id: 7, totalAmount: '85000.00'),
        ],
        total: 1,
      );
    });

    await tester.tap(find.text('TRX-007'));
    await settle(tester, frames: 14);

    expect(find.byType(TransactionDetailScreen), findsOneWidget);
    expect(
      recorded.map((RecordedRequest r) => r.apiPath),
      contains('/transactions/7'),
    );
  });

  testWidgets('a failed first page offers a retry that recovers', (
    WidgetTester tester,
  ) async {
    int calls = 0;
    await pumpScreen(tester, (_) async {
      calls++;
      if (calls == 1) {
        return transactionServerErrorResponse();
      }
      return emptyList();
    });

    expect(find.text('Could not load transactions'), findsOneWidget);
    expect(find.text('Something went wrong on the server.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await settle(tester);

    expect(find.text('No purchases yet'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('pull-to-refresh re-queries page one as the buyer', (
    WidgetTester tester,
  ) async {
    await pumpScreen(tester, (_) async => emptyList());
    expect(recorded, hasLength(1));
    expect(find.text('No purchases yet'), findsOneWidget);

    final RefreshIndicator indicator = tester.widget(
      find.byType(RefreshIndicator),
    );
    expect(indicator.onRefresh, isNotNull);
    await indicator.onRefresh();
    await settle(tester);

    expect(recorded, hasLength(2));
    expect(recorded.last.query['page'], '1');
    expect(recorded.last.query['role'], 'buyer');
    expect(recorded.last.query.containsKey('status'), isFalse);
    expect(find.text('No purchases yet'), findsOneWidget);
  });
}
