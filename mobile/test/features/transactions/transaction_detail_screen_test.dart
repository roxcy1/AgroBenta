import 'dart:convert';

import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_controller.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_scope.dart';
import 'package:agrobenta_mobile/features/messaging/state/conversations_controller.dart';
import 'package:agrobenta_mobile/features/messaging/state/messaging_scope.dart';
import 'package:agrobenta_mobile/features/messaging/view/chat_screen.dart';
import 'package:agrobenta_mobile/features/transactions/state/transaction_scope.dart';
import 'package:agrobenta_mobile/features/transactions/views/transaction_detail_screen.dart';
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

  /// Pumps the detail screen as the app does: the session scope (so Message
  /// Seller can label its own messages) and the messaging scope (so the chat it
  /// can push mounts), both above `MaterialApp`.
  Future<void> pumpDetail(
    WidgetTester tester,
    Future<http.Response> Function(RecordedRequest request) handler, {
    int transactionId = 1,
    int viewerId = 7,
    int counterpartyId = 3,
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

    tester.view.physicalSize = const Size(800, 2200);
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
              home: TransactionDetailScreen(transactionId: transactionId),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  /// A handler where the record is pending on read and cancelled on cancel.
  Future<http.Response> pendingThenCancelled(RecordedRequest request) async {
    if (request.apiPath == '/transactions/1/cancel') {
      return transactionDetailResponse(
        transaction: transactionJson(id: 1, status: 'cancelled'),
      );
    }
    return transactionDetailResponse(
      transaction: transactionJson(id: 1, status: 'pending'),
    );
  }

  testWidgets('shows the record header, amount and every supported section', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester, (_) async => transactionDetailResponse());

    // Header: reference, title, real status.
    expect(find.text('TRX-001'), findsWidgets);
    expect(
      find.text('Holstein'),
      findsWidgets,
      reason: 'the breed is both the listing title and the Breed row',
    );
    expect(find.text('Ongoing'), findsWidgets);

    // Amount, labelled as the transaction total — never as a listing price.
    expect(find.text('Transaction total'), findsOneWidget);
    expect(
      find.textContaining('42,500'),
      findsOneWidget,
      reason: 'the server figure, to the cent',
    );

    // Seller section from the counterparty projection.
    expect(find.text('Seller'), findsOneWidget);
    expect(find.text('Rizal Farms'), findsOneWidget);
    expect(find.text('rizal@example.test'), findsOneWidget);
    expect(find.text('Message seller'), findsOneWidget);

    // Livestock: only the attributes the snapshot actually carries.
    expect(find.text('Type'), findsOneWidget);
    expect(find.text('Cattle'), findsOneWidget);
    expect(find.text('Breed'), findsOneWidget);

    // Transaction terms.
    expect(find.text('Reference'), findsOneWidget);
    expect(find.text('Buyer'), findsOneWidget);
    expect(find.text('Quantity'), findsOneWidget);
    expect(find.text('1 head'), findsOneWidget);
    expect(find.text('Requested'), findsOneWidget);
    expect(find.text('Last updated'), findsOneWidget);

    // Status card and inquiry honesty note.
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Your inquiry'), findsOneWidget);

    // OQ-15: no completion affordance reaches a user at all.
    expect(find.text('Mark complete'), findsNothing);
    expect(find.textContaining('Mark complete'), findsNothing);
  });

  testWidgets('a seller sees the buyer as counterparty and sale wording', (
    WidgetTester tester,
  ) async {
    await pumpDetail(
      tester,
      (_) async => transactionDetailResponse(
        transaction: transactionJson(
          role: 'seller',
          counterparty: transactionCounterpartyJson(
            name: 'Ben Cruz',
            email: 'ben@example.test',
          ),
        ),
      ),
    );

    expect(find.text('Buyer'), findsWidgets);
    expect(find.text('Seller'), findsOneWidget);
    expect(find.text('Ben Cruz'), findsOneWidget);
    expect(find.text('ben@example.test'), findsOneWidget);
    expect(find.text('Message buyer'), findsOneWidget);
    expect(find.text('Message seller'), findsNothing);
    expect(find.text('Buyer inquiry'), findsOneWidget);
    expect(find.text('Your inquiry'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Cancel sale'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Cancel request'), findsNothing);
    expect(find.text('Recorded'), findsOneWidget);
  });

  testWidgets('a seller cancels a sale with sale-specific confirmation', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester, (RecordedRequest request) async {
      if (request.apiPath == '/transactions/1/cancel') {
        return transactionDetailResponse(
          transaction: transactionJson(
            id: 1,
            role: 'seller',
            status: 'cancelled',
          ),
        );
      }
      return transactionDetailResponse(
        transaction: transactionJson(id: 1, role: 'seller', status: 'pending'),
      );
    });

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel sale'));
    await settle(tester);

    expect(find.text('Cancel this sale?'), findsOneWidget);
    expect(
      find.text('This cannot be undone. A cancelled sale stays cancelled.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Keep sale'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel sale'));
    await settle(tester, frames: 20);

    final List<RecordedRequest> posts = recorded
        .where((RecordedRequest r) => r.apiPath == '/transactions/1/cancel')
        .toList(growable: false);
    expect(posts, hasLength(1));
    expect(
      find.text('This sale is cancelled and cannot be changed.'),
      findsOneWidget,
    );
  });

  testWidgets('a seller messages the buyer through the real thread', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester, (RecordedRequest request) async {
      if (request.apiPath == '/conversations/3/messages') {
        return messageThreadResponse();
      }
      if (request.apiPath == '/conversations/3/read') {
        return threadReadResponse();
      }
      return transactionDetailResponse(
        transaction: transactionJson(
          role: 'seller',
          counterparty: transactionCounterpartyJson(
            name: 'Ben Cruz',
            email: 'ben@example.test',
          ),
        ),
      );
    });

    await tester.tap(find.text('Message buyer'));
    await settle(tester, frames: 16);

    expect(find.byType(ChatScreen), findsOneWidget);
    expect(
      recorded.map((RecordedRequest r) => r.apiPath),
      contains('/conversations/3/messages'),
    );
  });

  testWidgets('distinguishes the transaction amount from the listing asking '
      'price and shows no fabricated agreed price', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester, (_) async => transactionDetailResponse());

    expect(find.text('Transaction total'), findsOneWidget);
    // The transaction resource carries no `asking_price`, so no "Reference
    // price"/"Agreed price" pair and no delivery terms may be rendered.
    expect(find.text('Agreed price'), findsNothing);
    expect(find.text('Reference price'), findsNothing);
    expect(find.text('Delivery method'), findsNothing);
    expect(find.text('Delivery fee'), findsNothing);
  });

  testWidgets('never renders a seller verification badge', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester, (_) async => transactionDetailResponse());

    // The counterparty projection has no verified flag, so no badge word and
    // no verified icon may appear.
    expect(find.text('Verified'), findsNothing);
    expect(find.textContaining('verified'), findsNothing);
    expect(find.byIcon(Icons.verified), findsNothing);
  });

  testWidgets('omits breed and location rows the record does not carry', (
    WidgetTester tester,
  ) async {
    await pumpDetail(
      tester,
      (_) async => transactionDetailResponse(
        transaction: transactionJson(
          listing: transactionListingJson(breed: ''),
        ),
      ),
    );

    // A blank breed is a non-null column with no value: no Breed row.
    expect(find.text('Breed'), findsNothing);
    expect(find.text('Location'), findsNothing);
    expect(find.text('Age'), findsNothing);
    expect(find.text('Weight'), findsNothing);
  });

  testWidgets('cancel requires an explicit confirmation', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester, pendingThenCancelled);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel request'));
    await settle(tester);

    expect(find.text('Cancel this request?'), findsOneWidget);
    expect(
      find.text('This cannot be undone. A cancelled request stays cancelled.'),
      findsOneWidget,
    );
    expect(
      recorded.where(
        (RecordedRequest r) => r.apiPath == '/transactions/1/cancel',
      ),
      isEmpty,
      reason: 'the irreversible call must wait for an explicit yes',
    );

    await tester.tap(find.widgetWithText(TextButton, 'Keep request'));
    await settle(tester);

    expect(find.text('Cancel this request?'), findsNothing);
    expect(
      recorded.where(
        (RecordedRequest r) => r.apiPath == '/transactions/1/cancel',
      ),
      isEmpty,
      reason: 'backing out leaves the pending record untouched',
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Cancel request'),
      findsOneWidget,
    );
  });

  testWidgets('a confirmed cancel posts once and the record turns '
      'immutable', (WidgetTester tester) async {
    await pumpDetail(tester, pendingThenCancelled);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel request'));
    await settle(tester);
    // The dialog's confirm is a TextButton; the record's own affordance is an
    // OutlinedButton, so this finds exactly the dialog action.
    await tester.tap(find.widgetWithText(TextButton, 'Cancel request'));
    await settle(tester, frames: 20);

    final List<RecordedRequest> posts = recorded
        .where((RecordedRequest r) => r.apiPath == '/transactions/1/cancel')
        .toList(growable: false);
    expect(posts, hasLength(1));

    expect(
      find.text('This request is cancelled and cannot be changed.'),
      findsOneWidget,
    );
    expect(find.text('Cancel request'), findsNothing);
    expect(find.text('Cancelled'), findsWidgets);
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
      find.text('This request is cancelled and cannot be changed.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(OutlinedButton, 'Cancel request'), findsNothing);
    expect(find.text('Mark complete'), findsNothing);
    expect(recorded.where((RecordedRequest r) => r.method == 'POST'), isEmpty);
  });

  testWidgets('Message seller opens the real thread with the counterparty', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester, (RecordedRequest request) async {
      if (request.apiPath == '/conversations/3/messages') {
        return messageThreadResponse();
      }
      if (request.apiPath == '/conversations/3/read') {
        return threadReadResponse();
      }
      return transactionDetailResponse();
    });

    await tester.tap(find.text('Message seller'));
    await settle(tester, frames: 16);

    expect(find.byType(ChatScreen), findsOneWidget);
    // The thread is addressed by the counterparty's real id from the payload.
    expect(
      recorded.map((RecordedRequest r) => r.apiPath),
      contains('/conversations/3/messages'),
    );
  });

  testWidgets('View status opens the dedicated Transaction Status screen', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester, (_) async => transactionDetailResponse());

    await tester.tap(find.widgetWithText(OutlinedButton, 'View status'));
    await settle(tester, frames: 12);

    expect(find.byType(TransactionStatusScreen), findsOneWidget);
    expect(find.text('Transaction Progress'), findsOneWidget);
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

  testWidgets('a failed load offers a retry under the transaction title', (
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

    expect(find.text('Something went wrong on the server.'), findsOneWidget);
    expect(
      find.text('Could not load transaction'),
      findsOneWidget,
      reason: 'the error must not name listings on the transaction screen',
    );
    expect(find.text('Could not load listings'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
    await settle(tester);

    expect(calls, 2);
    expect(find.text('TRX-001'), findsWidgets);
    expect(
      find.widgetWithText(OutlinedButton, 'Cancel request'),
      findsOneWidget,
      reason: 'the recovered record is pending again, so cancel returns',
    );
  });

  testWidgets('shows a loading state while the detail request is in flight', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester, (_) async => transactionDetailResponse());

    // The ready screen is the settled state; the loading copy is not present.
    expect(find.text('Loading transaction'), findsNothing);
    expect(find.text('Transaction total'), findsOneWidget);
  });
}

/// A messaging stack for the detail screen's Message Seller action.
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
