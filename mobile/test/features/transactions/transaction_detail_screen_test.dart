import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/transactions/state/transaction_scope.dart';
import 'package:agrobenta_mobile/features/transactions/views/transaction_detail_screen.dart';
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

  Future<void> settle(WidgetTester tester, {int frames = 10}) async {
    for (int frame = 0; frame < frames; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpDetail(
    WidgetTester tester,
    Future<http.Response> Function(RecordedRequest request) handler,
  ) async {
    final TransactionRepository repository = buildTransactionRepository(
      tokenStore,
      handler,
      recorded: recorded,
    );

    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      TransactionScope(
        repository: repository,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const TransactionDetailScreen(transactionId: 1),
        ),
      ),
    );
    await settle(tester);
  }

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

  testWidgets(
    'shows the full record, the counterparty contact and the viewer role',
    (WidgetTester tester) async {
      await pumpDetail(tester, (_) async => transactionDetailResponse());

      expect(find.text('TRX-001'), findsOneWidget);
      expect(find.text('Holstein'), findsOneWidget);
      expect(find.text('Ongoing'), findsOneWidget);
      expect(
        find.textContaining('42,500'),
        findsOneWidget,
        reason: 'the server figure, to the cent',
      );
      expect(find.text('1 head'), findsOneWidget);

      // Counterparty contact — the other party only, never both sides.
      expect(find.text('Rizal Farms'), findsOneWidget);
      expect(find.text('rizal@example.test'), findsOneWidget);
      expect(find.text('Buyer'), findsOneWidget);
      expect(find.text('Created'), findsOneWidget);
      expect(find.text('Updated'), findsOneWidget);

      // OQ-15: no "Mark complete" affordance reaches a user at all —
      // a button that always errors is worse than no button.
      expect(find.text('Mark complete'), findsNothing);
      expect(find.textContaining('Mark complete'), findsNothing);
    },
  );

  testWidgets('cancel requires an explicit confirmation', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester, pendingThenCancelled);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel transaction'));
    await settle(tester);

    expect(find.text('Cancel this transaction?'), findsOneWidget);
    expect(
      find.text('This cannot be undone. A cancelled transaction stays cancelled.'),
      findsOneWidget,
    );
    expect(
      recorded.where((RecordedRequest r) => r.method == 'POST'),
      isEmpty,
      reason: 'the irreversible call must wait for an explicit yes',
    );

    await tester.tap(find.widgetWithText(TextButton, 'Keep transaction'));
    await settle(tester);

    expect(find.text('Cancel this transaction?'), findsNothing);
    expect(
      recorded.where((RecordedRequest r) => r.method == 'POST'),
      isEmpty,
      reason: 'backing out leaves the pending record untouched',
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Cancel transaction'),
      findsOneWidget,
    );
  });

  testWidgets('a confirmed cancel posts once and the record turns '
      'immutable', (WidgetTester tester) async {
    await pumpDetail(tester, pendingThenCancelled);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel transaction'));
    await settle(tester);
    // The dialog's confirm is a TextButton; the record's own affordance is an
    // OutlinedButton, so this finds exactly the dialog action.
    await tester.tap(find.widgetWithText(TextButton, 'Cancel transaction'));
    await settle(tester, frames: 20);

    final List<RecordedRequest> posts = recorded
        .where((RecordedRequest r) => r.method == 'POST')
        .toList(growable: false);
    expect(posts, hasLength(1));
    expect(posts.single.apiPath, '/transactions/1/cancel');

    expect(
      find.text('This transaction is cancelled and cannot be changed.'),
      findsOneWidget,
    );
    expect(find.text('Cancel transaction'), findsNothing);
    expect(find.text('Ongoing'), findsNothing);
    expect(find.text('Cancelled'), findsOneWidget);
  });

  testWidgets('a terminal record gets an immutable notice, never a button', (
    WidgetTester tester,
  ) async {
    await pumpDetail(
      tester,
      (_) async => transactionDetailResponse(
        transaction: transactionJson(id: 1, status: 'cancelled'),
      ),
    );

    expect(
      find.text('This transaction is cancelled and cannot be changed.'),
      findsOneWidget,
    );
    expect(find.text('Cancel transaction'), findsNothing);
    expect(find.text('Mark complete'), findsNothing);
    expect(
      recorded.where((RecordedRequest r) => r.method == 'POST'),
      isEmpty,
    );
  });

  testWidgets('a 404 is an honest unavailable state, not a guess', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester, (_) async => transactionNotFoundResponse());

    expect(find.text('This transaction is not available'), findsOneWidget);
    expect(
      find.text('It may not exist, or you may not be a party to it.'),
      findsOneWidget,
    );
    expect(find.text('Back to transactions'), findsOneWidget);
  });

  testWidgets('a failed load offers a retry that recovers', (
    WidgetTester tester,
  ) async {
    int calls = 0;
    await pumpDetail(tester, (_) async {
      calls++;
      if (calls == 1) {
        return transactionServerErrorResponse();
      }
      return transactionDetailResponse();
    });

    expect(find.text('Server error.'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
    await settle(tester);

    expect(calls, 2);
    expect(find.text('TRX-001'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Cancel transaction'),
      findsOneWidget,
      reason: 'the recovered record is pending again, so cancel returns',
    );
  });
}
