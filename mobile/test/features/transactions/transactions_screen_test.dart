import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/transactions/state/transaction_scope.dart';
import 'package:agrobenta_mobile/features/transactions/views/transactions_screen.dart';
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
    Future<http.Response> Function(RecordedRequest request) handler,
  ) async {
    final TransactionRepository repository = buildTransactionRepository(
      tokenStore,
      handler,
      recorded: recorded,
    );

    // The default 800x600 surface is a couple of cards tall; a taller one
    // makes "the tab rendered its list" assertions meaningful.
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      TransactionScope(
        repository: repository,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const TransactionsScreen(),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('offers the three lifecycle tabs in order', (
    WidgetTester tester,
  ) async {
    await pumpScreen(tester, (_) async => transactionListResponse());

    final TabBar bar = tester.widget<TabBar>(find.byType(TabBar));
    expect(
      bar.tabs
          .map((Widget tab) => (tab as Tab).text)
          .toList(growable: false),
      <String>['Ongoing', 'Completed', 'Cancelled'],
    );
  });

  testWidgets('the Ongoing tab queries pending and renders its empty state', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      (_) async => transactionListResponse(
        transactions: <Map<String, dynamic>>[],
        total: 0,
      ),
    );

    expect(find.text('No ongoing transactions yet'), findsOneWidget);
    expect(
      find.text(
        'Transactions you start or receive will appear here while pending.',
      ),
      findsOneWidget,
    );
    expect(recorded, hasLength(1));
    expect(recorded.single.query['status'], 'pending');
  });

  testWidgets('each tab asks the server for its own status and is honest '
      'when empty', (WidgetTester tester) async {
    await pumpScreen(
      tester,
      (_) async => transactionListResponse(
        transactions: <Map<String, dynamic>>[],
        total: 0,
      ),
    );

    await tester.tap(find.text('Completed'));
    await settle(tester);

    expect(find.text('No completed transactions yet'), findsOneWidget);
    expect(
      find.text('Completion is not yet available in the app.'),
      findsOneWidget,
      reason:
          'no path in the app can reach completed today (OQ-15); the empty '
          'state says so rather than pretending',
    );
    expect(
      recorded.any((RecordedRequest r) => r.query['status'] == 'completed'),
      isTrue,
    );

    await tester.tap(find.text('Cancelled'));
    await settle(tester);

    expect(find.text('No cancelled transactions'), findsOneWidget);
    expect(
      recorded.any((RecordedRequest r) => r.query['status'] == 'cancelled'),
      isTrue,
    );
  });

  testWidgets('renders a card per record with id, title, amount and badge', (
    WidgetTester tester,
  ) async {
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
    expect(find.text('Ongoing'), findsWidgets);
    expect(
      find.textContaining('85,000'),
      findsOneWidget,
      reason: 'the amount shown is the server figure, formatted not computed',
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
      return transactionListResponse(
        transactions: <Map<String, dynamic>>[],
        total: 0,
      );
    });

    expect(find.text('Could not load transactions'), findsOneWidget);
    expect(find.text('Server error.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await settle(tester);

    expect(find.text('No ongoing transactions yet'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('pull-to-refresh re-queries page one', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      (_) async => transactionListResponse(
        transactions: <Map<String, dynamic>>[],
        total: 0,
      ),
    );
    expect(recorded, hasLength(1));
    expect(
      find.text('No ongoing transactions yet'),
      findsOneWidget,
      reason: 'the pending tab starts honestly empty',
    );

    // The indicator is wired to the controller's refresh flow: a pull must
    // re-query page one (page stays 1, status pending) without touching the
    // scroll position or the results already on screen.
    final RefreshIndicator indicator =
        tester.widget(find.byType(RefreshIndicator));
    expect(indicator.onRefresh, isNotNull,
        reason: 'refresh is wired to the controller');
    await indicator.onRefresh();
    await settle(tester);

    expect(recorded, hasLength(2));
    expect(
      recorded.last.query['page'],
      '1',
      reason: 'refresh always re-queries the first page',
    );
    expect(recorded.last.query['status'], 'pending');
    expect(find.text('No ongoing transactions yet'), findsOneWidget);
  });
}
