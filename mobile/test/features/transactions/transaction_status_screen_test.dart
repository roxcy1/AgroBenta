import 'dart:async';
import 'dart:convert';

import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_controller.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_scope.dart';
import 'package:agrobenta_mobile/features/messaging/state/conversations_controller.dart';
import 'package:agrobenta_mobile/features/messaging/state/messaging_scope.dart';
import 'package:agrobenta_mobile/features/messaging/view/chat_screen.dart';
import 'package:agrobenta_mobile/features/transactions/state/transaction_scope.dart';
import 'package:agrobenta_mobile/features/transactions/views/transaction_status_screen.dart';
import 'package:agrobenta_mobile/repositories/messaging_repository.dart';
import 'package:agrobenta_mobile/repositories/transaction_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/messaging_fakes.dart';
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

  Future<void> pumpStatus(
    WidgetTester tester,
    Future<http.Response> Function(RecordedRequest request) handler, {
    int transactionId = 1,
    int viewerId = 7,
  }) async {
    final TransactionRepository repository = buildTransactionRepository(
      tokenStore,
      handler,
      recorded: recorded,
    );

    final AuthController authController = AuthController(
      buildAuthRepository(
        tokenStore,
        (_) async => http.Response(
          jsonEncode(successEnvelope(data: userJson(id: viewerId))),
          200,
        ),
      ),
    );
    addTearDown(authController.dispose);
    tokenStore.token = 'stored-token';
    await authController.restoreSession();

    final MessagingRepositoryBundle messaging = await _buildMessaging(
      tokenStore,
      handler,
      recorded: recorded,
    );
    addTearDown(messaging.controller.dispose);

    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AuthScope(
        controller: authController,
        child: MessagingScope(
          repository: messaging.repository,
          conversationsController: messaging.controller,
          child: TransactionScope(
            repository: repository,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: TransactionStatusScreen(transactionId: transactionId),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('loads the record by id and shows the summary, id and date', (
    WidgetTester tester,
  ) async {
    await pumpStatus(tester, (_) async => transactionDetailResponse());

    expect(
      recorded.map((RecordedRequest r) => r.apiPath),
      contains('/transactions/1'),
      reason: 'the screen must load by the record identifier',
    );

    expect(find.text('Transaction Status'), findsOneWidget);
    // Listing title and the real status badge.
    expect(find.text('Holstein'), findsOneWidget);
    expect(find.text('Ongoing'), findsWidgets);
    // Server-derived total, labelled as the transaction total.
    expect(find.text('Transaction total'), findsOneWidget);
    expect(find.textContaining('42,500'), findsOneWidget);
    // Identity + the persisted timestamp.
    expect(find.text('Request ID'), findsOneWidget);
    expect(find.text('TRX-001'), findsOneWidget);
    expect(find.text('Requested'), findsOneWidget);
    expect(find.textContaining('2026'), findsWidgets);
  });

  testWidgets('maps a pending status to the real in-progress tracker', (
    WidgetTester tester,
  ) async {
    await pumpStatus(tester, (_) async => transactionDetailResponse());

    expect(find.text('Transaction Progress'), findsOneWidget);
    expect(find.text('Purchase request submitted'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    // The pending record's outcome is not yet known: never shown as completed.
    expect(
      find.textContaining('No outcome has been recorded yet'),
      findsOneWidget,
    );
  });

  testWidgets('maps a completed status to the completed outcome', (
    WidgetTester tester,
  ) async {
    await pumpStatus(
      tester,
      (_) async => transactionDetailResponse(
        transaction: transactionJson(status: 'completed'),
      ),
    );

    expect(find.text('Completed'), findsWidgets);
    expect(
      find.textContaining('recorded as complete and cannot change'),
      findsOneWidget,
    );
  });

  testWidgets('maps a cancelled status to a terminal, non-completed outcome', (
    WidgetTester tester,
  ) async {
    await pumpStatus(
      tester,
      (_) async => transactionDetailResponse(
        transaction: transactionJson(status: 'cancelled'),
      ),
    );

    expect(find.text('Cancelled'), findsWidgets);
    expect(
      find.textContaining('cannot change. It was not completed'),
      findsOneWidget,
    );
  });

  testWidgets('never fabricates step dates or unsupported workflow steps', (
    WidgetTester tester,
  ) async {
    await pumpStatus(tester, (_) async => transactionDetailResponse());

    // The design's reference steps exist only if the backend does. It does
    // not: there is no seller-acceptance, delivery or receipt step, so none
    // may be rendered as if recorded.
    expect(find.text('Pending Seller Confirmation'), findsNothing);
    expect(find.text('Seller Accepted'), findsNothing);
    expect(find.text('Arrange Delivery'), findsNothing);
    expect(find.text('Confirm Receipt / Mark as Completed'), findsNothing);
    // And no per-step time at all, since the backend records none.
    expect(find.textContaining('10:30 AM'), findsNothing);

    // The honest limitation is stated instead.
    expect(
      find.textContaining('records only the current status'),
      findsOneWidget,
    );
  });

  testWidgets('distinguishes the transaction total from the listing price', (
    WidgetTester tester,
  ) async {
    await pumpStatus(tester, (_) async => transactionDetailResponse());

    expect(find.text('Transaction total'), findsOneWidget);
    expect(find.text('Agreed price'), findsNothing);
    expect(find.text('Reference price'), findsNothing);
    expect(find.text('Delivery method'), findsNothing);
    expect(find.text('Delivery fee'), findsNothing);
  });

  testWidgets('never renders a seller verification badge or location', (
    WidgetTester tester,
  ) async {
    await pumpStatus(tester, (_) async => transactionDetailResponse());

    expect(find.text('Verified'), findsNothing);
    expect(find.textContaining('verified'), findsNothing);
    expect(find.byIcon(Icons.verified), findsNothing);
    expect(find.text('Location'), findsNothing);
  });

  testWidgets('Message Seller opens the real thread with the counterparty', (
    WidgetTester tester,
  ) async {
    await pumpStatus(tester, (RecordedRequest request) async {
      if (request.apiPath == '/conversations/3/messages') {
        return messageThreadResponse();
      }
      if (request.apiPath == '/conversations/3/read') {
        return threadReadResponse();
      }
      return transactionDetailResponse();
    });

    await tester.tap(find.text('Message Seller'));
    await settle(tester, frames: 16);

    expect(find.byType(ChatScreen), findsOneWidget);
    expect(
      recorded.map((RecordedRequest r) => r.apiPath),
      contains('/conversations/3/messages'),
    );
  });

  testWidgets('a 404 is an honest missing/unauthorized state', (
    WidgetTester tester,
  ) async {
    await pumpStatus(tester, (_) async => transactionNotFoundResponse());

    expect(find.text('This status is not available'), findsOneWidget);
    expect(
      find.textContaining('may not exist, or you may not be a party'),
      findsOneWidget,
    );
    expect(find.text('Back to transactions'), findsOneWidget);
    // No fabricated tracker leaks into the unavailable state.
    expect(find.text('Transaction Progress'), findsNothing);
  });

  testWidgets('a failed load offers a retry under the status title', (
    WidgetTester tester,
  ) async {
    int calls = 0;
    await pumpStatus(tester, (_) async {
      calls++;
      if (calls == 1) {
        return transactionServerErrorResponse();
      }
      return transactionDetailResponse();
    });

    expect(find.text('Server error.'), findsOneWidget);
    expect(find.text('Could not load status'), findsOneWidget);
    expect(find.text('Could not load listings'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
    await settle(tester);

    expect(calls, 2);
    expect(find.text('Transaction Progress'), findsOneWidget);
  });

  testWidgets('shows a loading state before the record resolves', (
    WidgetTester tester,
  ) async {
    // The response is held open, so the load future cannot complete while the
    // loading frame is asserted.
    final Completer<http.Response> held = Completer<http.Response>();
    final TransactionRepository repository = buildTransactionRepository(
      tokenStore,
      (_) => held.future,
      recorded: recorded,
    );

    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      TransactionScope(
        repository: repository,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const TransactionStatusScreen(transactionId: 1),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Loading status'), findsOneWidget);
    expect(find.text('Transaction Progress'), findsNothing);

    held.complete(transactionDetailResponse());
    await settle(tester, frames: 12);
    expect(find.text('Loading status'), findsNothing);
    expect(find.text('Transaction Progress'), findsOneWidget);
  });
}

class MessagingRepositoryBundle {
  const MessagingRepositoryBundle({
    required this.repository,
    required this.controller,
  });

  final MessagingRepository repository;
  final ConversationsController controller;
}

Future<MessagingRepositoryBundle> _buildMessaging(
  FakeTokenStore tokenStore,
  Future<http.Response> Function(RecordedRequest request) handler, {
  List<RecordedRequest>? recorded,
}) async {
  final MessagingRepository repository = buildMessagingRepository(
    tokenStore,
    handler,
    recorded: recorded,
  );
  return MessagingRepositoryBundle(
    repository: repository,
    controller: ConversationsController(repository),
  );
}
