import 'dart:convert';

import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_controller.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_scope.dart';
import 'package:agrobenta_mobile/features/inquiries/state/inquiry_scope.dart';
import 'package:agrobenta_mobile/features/messaging/state/conversations_controller.dart';
import 'package:agrobenta_mobile/features/messaging/state/messaging_scope.dart';
import 'package:agrobenta_mobile/features/messaging/view/chat_screen.dart';
import 'package:agrobenta_mobile/features/offers/state/offer_scope.dart';
import 'package:agrobenta_mobile/features/transactions/state/transaction_scope.dart';
import 'package:agrobenta_mobile/models/message.dart';
import 'package:agrobenta_mobile/repositories/inquiry_repository.dart';
import 'package:agrobenta_mobile/repositories/messaging_repository.dart';
import 'package:agrobenta_mobile/repositories/offer_repository.dart';
import 'package:agrobenta_mobile/repositories/transaction_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/inquiry_fakes.dart';
import '../../support/messaging_fakes.dart';
import '../../support/offer_fakes.dart';
import '../../support/transaction_fakes.dart';

/// Accepting an offer creates a real pending transaction in one request, so the
/// buyer is asked to confirm first, as they are for Decline and Withdraw. A
/// mis-tap on "Accept offer" must not create anything.
void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  setUp(() {
    tokenStore = FakeTokenStore('1|mobile-token');
    recorded = <RecordedRequest>[];
  });

  Future<void> settle(WidgetTester tester) async {
    for (int frame = 0; frame < 16; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// The buyer (user 7) in a thread with the seller (user 3) who has a pending
  /// offer for them.
  Future<void> pumpBuyerChat(WidgetTester tester) async {
    Future<http.Response> handler(RecordedRequest request) async {
      if (request.apiPath == '/offers' && request.method == 'GET') {
        return offersResponse(
          offers: <Map<String, dynamic>>[
            offerJson(id: 1, sellerId: 3, buyerId: 7, status: 'pending'),
          ],
        );
      }
      if (request.apiPath == '/offers/1/accept' && request.method == 'POST') {
        return offerAcceptedResponse();
      }
      if (request.method == 'POST') {
        return threadReadResponse();
      }
      return messageThreadResponse();
    }

    final MessagingRepository messaging = buildMessagingRepository(
      tokenStore,
      handler,
      recorded: recorded,
    );
    final ConversationsController conversations = ConversationsController(
      messaging,
    );
    addTearDown(conversations.dispose);
    final OfferRepository offers = buildOfferRepository(
      tokenStore,
      handler,
      recorded: recorded,
    );
    final InquiryRepository inquiries = buildInquiryRepository(
      tokenStore,
      handler,
      recorded: recorded,
    );
    final TransactionRepository transactions = buildTransactionRepository(
      tokenStore,
      handler,
      recorded: recorded,
    );

    final AuthController auth = AuthController(
      buildAuthRepository(
        tokenStore,
        (_) async => http.Response(
          jsonEncode(successEnvelope(data: userJson(id: 7))),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(auth.dispose);
    tokenStore.token = 'stored-token';
    await auth.restoreSession();

    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MessagingScope(
        repository: messaging,
        conversationsController: conversations,
        child: OfferScope(
          repository: offers,
          child: InquiryScope(
            repository: inquiries,
            child: TransactionScope(
              repository: transactions,
              child: AuthScope(
                controller: auth,
                child: MaterialApp(
                  theme: AppTheme.light(),
                  home: const ChatScreen(
                    counterpart: ChatUser(
                      id: 3,
                      name: 'Rizal Farms',
                      avatarUrl: null,
                    ),
                    currentUserId: 7,
                    counterpartRole: 'Seller',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  int acceptCalls() => recorded
      .where(
        (RecordedRequest r) =>
            r.method == 'POST' && r.apiPath == '/offers/1/accept',
      )
      .length;

  final Finder panelAccept = find.widgetWithText(FilledButton, 'Accept offer');
  final Finder dialog = find.byType(AlertDialog);
  final Finder dialogAccept = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.text('Accept offer'),
  );

  testWidgets('tapping Accept offer asks first and creates nothing yet', (
    WidgetTester tester,
  ) async {
    await pumpBuyerChat(tester);
    expect(panelAccept, findsOneWidget);

    await tester.tap(panelAccept);
    await settle(tester);

    expect(dialog, findsOneWidget);
    expect(find.text('Accept this offer?'), findsOneWidget);
    expect(
      find.textContaining('creates a pending transaction'),
      findsOneWidget,
    );
    expect(
      find.textContaining('directly between you and the seller'),
      findsOneWidget,
    );
    expect(acceptCalls(), 0, reason: 'nothing is sent before the buyer agrees');
    expect(find.text('Offer accepted'), findsNothing);
  });

  testWidgets('"Not yet" closes the question and sends nothing', (
    WidgetTester tester,
  ) async {
    await pumpBuyerChat(tester);

    await tester.tap(panelAccept);
    await settle(tester);
    await tester.tap(find.text('Not yet'));
    await settle(tester);

    expect(dialog, findsNothing);
    expect(acceptCalls(), 0);
    expect(panelAccept, findsOneWidget, reason: 'the offer is still pending');
  });

  testWidgets('dismissing the question outside the dialog sends nothing', (
    WidgetTester tester,
  ) async {
    await pumpBuyerChat(tester);

    await tester.tap(panelAccept);
    await settle(tester);
    await tester.tapAt(const Offset(4, 4));
    await settle(tester);

    expect(dialog, findsNothing);
    expect(acceptCalls(), 0);
    expect(panelAccept, findsOneWidget);
  });

  testWidgets('confirming accepts the offer once and then reports it', (
    WidgetTester tester,
  ) async {
    await pumpBuyerChat(tester);

    await tester.tap(panelAccept);
    await settle(tester);
    await tester.tap(dialogAccept);
    await settle(tester);

    expect(acceptCalls(), 1);
    expect(find.text('Offer accepted'), findsOneWidget);
    expect(find.text('Accept this offer?'), findsNothing);
  });
}
