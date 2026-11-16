import 'dart:convert';

import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_controller.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_scope.dart';
import 'package:agrobenta_mobile/features/inquiries/state/inquiry_scope.dart';
import 'package:agrobenta_mobile/features/inquiries/view/received_inquiries_screen.dart';
import 'package:agrobenta_mobile/features/marketplace/state/marketplace_controller.dart';
import 'package:agrobenta_mobile/features/marketplace/state/marketplace_scope.dart';
import 'package:agrobenta_mobile/features/messaging/state/conversations_controller.dart';
import 'package:agrobenta_mobile/features/messaging/state/messaging_scope.dart';
import 'package:agrobenta_mobile/features/messaging/view/chat_screen.dart';
import 'package:agrobenta_mobile/features/offers/state/offer_scope.dart';
import 'package:agrobenta_mobile/features/offers/view/make_offer_screen.dart';
import 'package:agrobenta_mobile/repositories/inquiry_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/inquiry_fakes.dart';
import '../../support/messaging_fakes.dart';
import '../../support/marketplace_fakes.dart';
import '../../support/offer_fakes.dart';

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

  Future<void> pumpScreen(
    WidgetTester tester,
    Future<http.Response> Function(RecordedRequest request) handler,
  ) async {
    final InquiryRepository repository = buildInquiryRepository(
      tokenStore,
      handler,
      recorded: recorded,
    );
    // The card action pushes the make-offer route, which reads this scope.
    final offerRepository = buildOfferRepository(
      tokenStore,
      (_) async => offersResponse(offers: <Map<String, dynamic>>[]),
      recorded: recorded,
    );
    final marketplaceRepository = buildMarketplaceRepository(
      tokenStore,
      (_) async => listingDetailResponse(listing: listingJson()),
      recorded: recorded,
    );
    final marketplaceController = MarketplaceController(marketplaceRepository);

    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      InquiryScope(
        repository: repository,
        child: MarketplaceScope(
          repository: marketplaceRepository,
          controller: marketplaceController,
          child: OfferScope(
            repository: offerRepository,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const ReceivedInquiriesScreen(),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets(
    'shows the empty state, not an error, when there are no inquiries',
    (WidgetTester tester) async {
      await pumpScreen(
        tester,
        (_) async => sellerInquiryListResponse(
          inquiries: <Map<String, dynamic>>[],
          total: 0,
        ),
      );

      expect(find.text('Received Inquiries'), findsOneWidget);
      expect(find.text('No inquiries yet'), findsOneWidget);
      expect(find.text('Could not load received inquiries'), findsNothing);
      expect(recorded.single.apiPath, '/seller/inquiries');
    },
  );

  testWidgets('an ineligible inquiry offers no Make an offer action', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      (_) async => sellerInquiryListResponse(
        inquiries: <Map<String, dynamic>>[
          sellerInquiryJson(canMakeOffer: false),
        ],
      ),
    );

    expect(find.text('Make an offer'), findsNothing);
  });

  testWidgets('renders the buyer inquiry fields the resource carries', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      (_) async => sellerInquiryListResponse(
        inquiries: <Map<String, dynamic>>[
          sellerInquiryJson(
            buyer: inquiryBuyerJson(name: 'Maria Santos'),
            listing: inquiryListingJson(
              livestockType: 'Cattle',
              breed: 'Holstein',
            ),
            subject: 'Interested in your cattle',
            message: 'Is this one still available?',
            purchaseInterest: true,
            transactionMethod: 'direct_deal',
            deliveryMethod: 'buyer_pickup',
            contactMethod: 'in_app_message',
            preferredSchedule: '2026-10-25',
          ),
        ],
      ),
    );

    expect(find.text('Maria Santos'), findsOneWidget);
    expect(find.text('Cattle - Holstein'), findsOneWidget);
    expect(find.text('Interested in your cattle'), findsOneWidget);
    expect(find.text('Is this one still available?'), findsOneWidget);
    expect(find.text('Wants to buy'), findsOneWidget);
    expect(
      find.text(
        'Cash / Pick up from the seller\'s farm / Direct Deal / Buyer Pickup '
        '/ In-app Message',
      ),
      findsOneWidget,
    );
    expect(find.text('Preferred date: 25 Oct 2026'), findsOneWidget);
    expect(find.text('Proposed delivery fee: ₱1,500.00'), findsOneWidget);
    // The structured offer is the seller's only response action.
    expect(find.text('Make an offer'), findsOneWidget);
  });

  testWidgets('renders a relative collection-date preference', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      (_) async => sellerInquiryListResponse(
        inquiries: <Map<String, dynamic>>[
          sellerInquiryJson(
            collectionDateOption: 'next_few_days',
            preferredSchedule: null,
          ),
        ],
      ),
    );

    expect(
      find.text('Collection plan: Within the next few days'),
      findsOneWidget,
    );
  });

  testWidgets('a deleted listing and missing buyer stay readable', (
    WidgetTester tester,
  ) async {
    final Map<String, dynamic> inquiry = sellerInquiryJson();
    inquiry['buyer'] = null;
    inquiry['listing'] = null;

    await pumpScreen(
      tester,
      (_) async =>
          sellerInquiryListResponse(inquiries: <Map<String, dynamic>>[inquiry]),
    );

    expect(find.text('Unknown buyer'), findsOneWidget);
    expect(find.text('Listing no longer available'), findsOneWidget);
    expect(find.text('Is this one still available?'), findsOneWidget);
    // Without both identities the offer form is not offered at all.
    expect(find.text('Make an offer'), findsNothing);
  });

  testWidgets('a first-page failure shows the message and retries', (
    WidgetTester tester,
  ) async {
    int calls = 0;
    await pumpScreen(tester, (_) async {
      calls++;
      if (calls == 1) {
        return inquiryServerErrorResponse();
      }
      return sellerInquiryListResponse(
        inquiries: <Map<String, dynamic>>[
          sellerInquiryJson(buyer: inquiryBuyerJson(name: 'Ben Cruz')),
        ],
      );
    });

    expect(find.text('Could not load received inquiries'), findsOneWidget);
    expect(find.text('Something went wrong on the server.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await settle(tester);

    expect(find.text('Ben Cruz'), findsOneWidget);
    expect(recorded, hasLength(2));
  });

  testWidgets('the structured offer action opens the seller form', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      (_) async => sellerInquiryListResponse(
        inquiries: <Map<String, dynamic>>[
          sellerInquiryJson(
            buyer: inquiryBuyerJson(name: 'Maria Santos'),
            listing: inquiryListingJson(
              livestockType: 'Cattle',
              breed: 'Holstein',
            ),
          ),
        ],
      ),
    );

    await tester.tap(find.text('Make an offer'));
    await settle(tester);

    expect(find.byType(MakeOfferScreen), findsOneWidget);
    expect(find.text('Send offer'), findsOneWidget);
    expect(
      find.text('Maria Santos'),
      findsWidgets,
      reason: 'the offer form names the inquiry buyer',
    );
  });

  testWidgets('Open Conversation opens the pair chat without creating a thread', (
    WidgetTester tester,
  ) async {
    final InquiryRepository repository = buildInquiryRepository(
      tokenStore,
      (_) async => sellerInquiryListResponse(
        inquiries: <Map<String, dynamic>>[
          sellerInquiryJson(buyer: inquiryBuyerJson(id: 9, name: 'Maria Santos')),
        ],
      ),
      recorded: recorded,
    );
    final offerRepository = buildOfferRepository(
      tokenStore,
      (_) async => offersResponse(offers: <Map<String, dynamic>>[]),
      recorded: recorded,
    );
    final messagingRepository = buildMessagingRepository(
      tokenStore,
      (RecordedRequest request) async {
        if (request.method == 'GET' && request.apiPath.endsWith('/messages')) {
          return messageThreadResponse();
        }
        return threadReadResponse();
      },
      recorded: recorded,
    );
    final ConversationsController conversationsController =
        ConversationsController(messagingRepository);
    addTearDown(conversationsController.dispose);

    final AuthController authController = AuthController(
      buildAuthRepository(
        tokenStore,
        (_) async => http.Response(
          jsonEncode(successEnvelope(data: userJson(id: 3))),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(authController.dispose);
    tokenStore.token = 'stored-token';
    await authController.restoreSession();

    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      InquiryScope(
        repository: repository,
        child: OfferScope(
          repository: offerRepository,
          child: MessagingScope(
            repository: messagingRepository,
            conversationsController: conversationsController,
            child: AuthScope(
              controller: authController,
              child: MaterialApp(
                theme: AppTheme.light(),
                home: const ReceivedInquiriesScreen(),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    await tester.ensureVisible(find.text('Open conversation'));
    await tester.pump();
    await tester.tap(find.text('Open conversation'));
    await settle(tester);

    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text('Maria Santos'), findsWidgets);
    expect(
      recorded.where(
        (RecordedRequest r) =>
            r.method == 'GET' && r.apiPath == '/conversations/9/messages',
      ),
      hasLength(1),
      reason: 'the existing buyer–seller thread is loaded by pair id',
    );
    expect(
      recorded.where((RecordedRequest r) => r.apiPath == '/messages'),
      isEmpty,
      reason: 'opening a conversation must not send or create a message',
    );
  });

  testWidgets('an inquiry without a buyer projection hides the chat action', (
    WidgetTester tester,
  ) async {
    final Map<String, dynamic> inquiry = sellerInquiryJson();
    inquiry['buyer'] = null;

    await pumpScreen(
      tester,
      (_) async => sellerInquiryListResponse(
        inquiries: <Map<String, dynamic>>[inquiry],
      ),
    );

    expect(find.text('Open conversation'), findsNothing);
  });
}
