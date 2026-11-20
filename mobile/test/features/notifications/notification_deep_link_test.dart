import 'dart:convert';

import 'package:agrobenta_mobile/core/storage/account_mode_preference_store.dart';
import 'package:agrobenta_mobile/features/messaging/view/chat_screen.dart';
import 'package:agrobenta_mobile/features/notifications/view/notifications_screen.dart';
import 'package:agrobenta_mobile/features/seller_listings/state/seller_listing_scope.dart';
import 'package:agrobenta_mobile/features/seller_listings/view/seller_listing_detail_screen.dart';
import 'package:agrobenta_mobile/features/seller_listings/view/seller_listings_screen.dart';
import 'package:agrobenta_mobile/features/seller_verification/view/seller_verification_screen.dart';
import 'package:agrobenta_mobile/features/transactions/views/transaction_detail_screen.dart';
import 'package:agrobenta_mobile/main.dart';
import 'package:agrobenta_mobile/models/app_notification.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/auth_fakes.dart';
import '../../support/marketplace_fakes.dart';
import '../../support/messaging_fakes.dart';
import '../../support/notification_fakes.dart';
import '../../support/push_fakes.dart';
import '../../support/seller_listing_fakes.dart' show sellerListingListResponse;
import '../../support/transaction_fakes.dart';

class _MemoryAccountModeStore implements AccountModePreferenceStore {
  @override
  Future<String?> read(int userId) async => null;

  @override
  Future<void> write(int userId, String mode) async {}
}

Future<void> _settle(WidgetTester tester) async {
  for (int frame = 0; frame < 12; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: const <String, String>{'content-type': 'application/json'},
);

/// Tapping a notification opens what it is about and still marks it read.
void main() {
  late List<RecordedRequest> recorded;
  late List<Map<String, dynamic>> conversations;
  late int conversationsStatus;
  late Map<String, dynamic> me;
  late List<Map<String, dynamic>> sellerListings;

  setUp(() {
    recorded = <RecordedRequest>[];
    conversations = <Map<String, dynamic>>[];
    conversationsStatus = 200;
    me = userJson(id: 7);
    sellerListings = <Map<String, dynamic>>[];
  });

  /// Signs in, opens Notifications from the Home bell and taps [notification]
  /// [taps] times in a row, without letting a frame pass between taps.
  /// [beforeTap] runs once the Notifications screen is showing.
  Future<void> tapNotification(
    WidgetTester tester,
    Map<String, dynamic> notification, {
    int taps = 1,
    Future<void> Function(WidgetTester tester)? beforeTap,
  }) async {
    final MockClient client = MockClient((http.Request request) async {
      final RecordedRequest entry = RecordedRequest(request);
      recorded.add(entry);
      switch (entry.apiPath) {
        case '/auth/me':
          return _json(successEnvelope(data: me));
        case '/devices':
          return deviceRegisteredResponse();
        case '/conversations':
          return conversationsStatus == 200
              ? conversationsResponse(conversations: conversations)
              : _json(<String, dynamic>{
                  'message': 'Server Error',
                }, status: conversationsStatus);
        case '/seller/listings':
          return sellerListingListResponse(
            listings: sellerListings,
            total: sellerListings.length,
          );
        case '/listings':
          return marketplaceListResponse(listings: const [], total: 0);
        case '/marketplace/popular-livestock':
          return popularLivestockResponse();
        case '/transactions':
          return transactionListResponse(transactions: const [], total: 0);
        case '/notifications':
          return notificationsPageResponse(
            notifications: <Map<String, dynamic>>[notification],
            unreadCount: 1,
          );
        case '/notifications/unread-count':
          return unreadCountResponse(count: 1);
        default:
          return _json(<String, dynamic>{'message': 'Not found.'}, status: 404);
      }
    });
    addTearDown(client.close);

    await tester.pumpWidget(
      AgroBentaApp(
        tokenStore: FakeTokenStore('user-a-token'),
        accountModePreferenceStore: _MemoryAccountModeStore(),
        httpClient: client,
      ),
    );
    await _settle(tester);
    await tester.tap(find.byTooltip('Notifications'));
    await _settle(tester);
    expect(find.byType(NotificationsScreen), findsOneWidget);
    await beforeTap?.call(tester);

    final Finder tile = find.text(notification['title'] as String);
    for (int tap = 0; tap < taps; tap++) {
      await tester.tap(tile);
    }
    await _settle(tester);
  }

  /// Counts [type] across every route, including ones covered by another.
  int screensOf(Type type) =>
      find.byType(type, skipOffstage: false).evaluate().length;

  bool markedRead(String id) => recorded.any(
    (RecordedRequest r) =>
        r.method == 'PATCH' && r.apiPath == '/notifications/$id/read',
  );

  test('reads the inquiry thread keys from the resource', () {
    final AppNotification notification = AppNotification.fromJson(
      notificationJson(
        type: 'inquiry',
        action: 'inquiry',
        actionId: 3,
        listingId: 12,
      ),
    );

    expect(notification.action, NotificationAction.inquiry);
    expect(notification.actionId, 3);
    expect(notification.listingId, 12);
    expect(notification.markRead().listingId, 12);
    expect(AppNotification.fromJson(notificationJson()).listingId, isNull);
  });

  testWidgets('a message notification opens that conversation', (
    WidgetTester tester,
  ) async {
    conversations = <Map<String, dynamic>>[
      conversationJson(
        counterpart: chatUserJson(id: 8, name: 'Someone else'),
        listingId: 12,
      ),
      conversationJson(
        counterpart: chatUserJson(id: 3, name: 'Rizal Farms'),
        listingId: 12,
        listingTitle: 'Holstein Heifer',
        roles: const <String>['seller'],
      ),
    ];

    await tapNotification(
      tester,
      notificationJson(
        id: 'n-inquiry',
        title: 'New inquiry',
        type: 'inquiry',
        action: 'inquiry',
        actionId: 3,
        listingId: 12,
      ),
    );

    final ChatScreen chat = tester.widget<ChatScreen>(find.byType(ChatScreen));
    expect(chat.counterpart.id, 3);
    expect(chat.counterpart.name, 'Rizal Farms');
    expect(chat.currentUserId, 7);
    expect(chat.listingTitle, 'Holstein Heifer');
    expect(markedRead('n-inquiry'), isTrue);
  });

  testWidgets("prefers the thread about the notification's listing", (
    WidgetTester tester,
  ) async {
    conversations = <Map<String, dynamic>>[
      conversationJson(
        counterpart: chatUserJson(id: 3, name: 'Rizal Farms'),
        listingId: 99,
        listingTitle: 'Brahman Bull',
      ),
      conversationJson(
        counterpart: chatUserJson(id: 3, name: 'Rizal Farms'),
        listingId: 12,
        listingTitle: 'Holstein Heifer',
      ),
    ];

    await tapNotification(
      tester,
      notificationJson(
        id: 'n-two-threads',
        title: 'New inquiry',
        type: 'inquiry',
        action: 'inquiry',
        actionId: 3,
        listingId: 12,
      ),
    );

    // The listing-12 thread opens, though the listing-99 one comes first.
    expect(
      tester.widget<ChatScreen>(find.byType(ChatScreen)).listingTitle,
      'Holstein Heifer',
    );
  });

  testWidgets(
    'an older notification without listing_id opens any thread with that person',
    (WidgetTester tester) async {
      conversations = <Map<String, dynamic>>[
        conversationJson(
          counterpart: chatUserJson(id: 8, name: 'Someone else'),
          listingId: 12,
        ),
        conversationJson(
          counterpart: chatUserJson(id: 3, name: 'Rizal Farms'),
          listingId: 99,
          listingTitle: 'Brahman Bull',
        ),
      ];

      await tapNotification(
        tester,
        notificationJson(
          id: 'n-legacy',
          title: 'New inquiry',
          type: 'inquiry',
          action: 'inquiry',
          actionId: 3,
        ),
      );

      final ChatScreen chat = tester.widget<ChatScreen>(
        find.byType(ChatScreen),
      );
      expect(chat.counterpart.id, 3);
      expect(chat.listingTitle, 'Brahman Bull');
    },
  );

  testWidgets('a failed inbox refresh says so, not that the thread is gone', (
    WidgetTester tester,
  ) async {
    conversationsStatus = 500;

    await tapNotification(
      tester,
      notificationJson(
        id: 'n-offline',
        title: 'New inquiry',
        type: 'inquiry',
        action: 'inquiry',
        actionId: 3,
        listingId: 12,
      ),
    );

    expect(find.byType(ChatScreen), findsNothing);
    expect(
      find.text(
        'Could not load your conversations. Check your connection and try '
        'again.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('This conversation is no longer available.'),
      findsNothing,
    );
    expect(markedRead('n-offline'), isTrue);
  });

  // The regression test for the double-tap guard: the chat opens only after
  // the inbox re-read, so without the guard every tap during that request
  // stacks another chat.
  testWidgets('rapid taps on a message open one chat', (
    WidgetTester tester,
  ) async {
    conversations = <Map<String, dynamic>>[
      conversationJson(
        counterpart: chatUserJson(id: 3, name: 'Rizal Farms'),
        listingId: 12,
      ),
    ];

    await tapNotification(
      tester,
      notificationJson(
        id: 'n-rapid-chat',
        title: 'New inquiry',
        type: 'inquiry',
        action: 'inquiry',
        actionId: 3,
        listingId: 12,
      ),
      taps: 3,
    );

    expect(screensOf(ChatScreen), 1);
  });

  // A screen pushed straight away is already protected by the Navigator, which
  // ignores taps on the covered route during the transition; this pins that
  // the result stays one screen.
  testWidgets('rapid taps on a transaction open one screen', (
    WidgetTester tester,
  ) async {
    await tapNotification(
      tester,
      notificationJson(
        id: 'n-rapid-tx',
        title: 'New transaction',
        type: 'transactions',
        action: 'transaction',
        actionId: 41,
      ),
      taps: 3,
    );

    expect(screensOf(TransactionDetailScreen), 1);
  });

  testWidgets('a message whose thread is gone stays on Notifications', (
    WidgetTester tester,
  ) async {
    await tapNotification(
      tester,
      notificationJson(
        id: 'n-gone',
        title: 'New inquiry',
        type: 'inquiry',
        action: 'inquiry',
        actionId: 3,
        listingId: 12,
      ),
    );

    expect(find.byType(ChatScreen), findsNothing);
    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(
      find.text('This conversation is no longer available.'),
      findsOneWidget,
    );
    expect(markedRead('n-gone'), isTrue);
  });

  testWidgets('a transaction notification opens the transaction', (
    WidgetTester tester,
  ) async {
    await tapNotification(
      tester,
      notificationJson(
        id: 'n-tx',
        title: 'New transaction',
        type: 'transactions',
        action: 'transaction',
        actionId: 41,
      ),
    );

    final TransactionDetailScreen detail = tester
        .widget<TransactionDetailScreen>(find.byType(TransactionDetailScreen));
    expect(detail.transactionId, 41);
    expect(markedRead('n-tx'), isTrue);
  });

  testWidgets('a listing notification opens My Listings', (
    WidgetTester tester,
  ) async {
    await tapNotification(
      tester,
      notificationJson(
        id: 'n-listing',
        title: 'Listing approved',
        type: 'listing',
        action: 'listing',
        actionId: 12,
      ),
    );

    // The listing is not in a loaded My Listings page, so the list opens.
    expect(find.byType(SellerListingsScreen), findsOneWidget);
    expect(markedRead('n-listing'), isTrue);
  });

  testWidgets('a listing in the loaded My Listings page opens its detail', (
    WidgetTester tester,
  ) async {
    me = userJson(id: 7, sellerCapability: 'seller');
    sellerListings = <Map<String, dynamic>>[listingJson(id: 12)];

    await tapNotification(
      tester,
      notificationJson(
        id: 'n-listing-loaded',
        title: 'Listing approved',
        type: 'listing',
        action: 'listing',
        actionId: 12,
      ),
      beforeTap: (WidgetTester tester) async {
        await SellerListingScope.readOf(
          tester.element(find.byType(NotificationsScreen)),
        ).loadInitial();
        await _settle(tester);
      },
    );

    final SellerListingDetailScreen detail = tester
        .widget<SellerListingDetailScreen>(
          find.byType(SellerListingDetailScreen),
        );
    expect(detail.listing.id, 12);
    expect(find.byType(SellerListingsScreen), findsNothing);
    expect(markedRead('n-listing-loaded'), isTrue);
  });

  testWidgets('a verification notification opens seller verification', (
    WidgetTester tester,
  ) async {
    await tapNotification(
      tester,
      notificationJson(
        id: 'n-verify',
        title: 'Seller verification approved',
        type: 'seller_verification',
        action: 'verification',
        actionId: 5,
      ),
    );

    expect(find.byType(SellerVerificationScreen), findsOneWidget);
    expect(markedRead('n-verify'), isTrue);
  });

  for (final (String label, String action, int? actionId)
      in <(String, String, int?)>[
        ('no target', 'none', null),
        ('an unknown action', 'something_new', 9),
        ('a missing id', 'transaction', null),
      ]) {
    testWidgets('$label stays on Notifications', (WidgetTester tester) async {
      await tapNotification(
        tester,
        notificationJson(
          id: 'n-stay',
          title: 'Heads up',
          type: 'system',
          action: action,
          actionId: actionId,
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(find.byType(TransactionDetailScreen), findsNothing);
      expect(markedRead('n-stay'), isTrue);
    });
  }
}
