import 'dart:async';
import 'dart:convert';

import 'package:agrobenta_mobile/core/realtime/realtime_event.dart';
import 'package:agrobenta_mobile/features/inquiries/state/active_inquiries_controller.dart';
import 'package:agrobenta_mobile/features/marketplace/state/marketplace_controller.dart';
import 'package:agrobenta_mobile/features/marketplace/state/marketplace_state.dart';
import 'package:agrobenta_mobile/features/messaging/state/chat_controller.dart';
import 'package:agrobenta_mobile/features/messaging/state/messaging_state.dart';
import 'package:agrobenta_mobile/features/notifications/state/notifications_controller.dart';
import 'package:agrobenta_mobile/features/notifications/state/notifications_state.dart';
import 'package:agrobenta_mobile/features/offers/state/chat_offers_controller.dart';
import 'package:agrobenta_mobile/features/offers/state/offer_state.dart';
import 'package:agrobenta_mobile/features/seller_dashboard/state/seller_dashboard_controller.dart';
import 'package:agrobenta_mobile/features/seller_dashboard/state/seller_dashboard_state.dart';
import 'package:agrobenta_mobile/features/seller_listings/state/seller_listing_controller.dart';
import 'package:agrobenta_mobile/features/seller_listings/state/seller_listing_state.dart';
import 'package:agrobenta_mobile/features/seller_verification/state/seller_verification_controller.dart';
import 'package:agrobenta_mobile/features/seller_verification/state/seller_verification_state.dart';
import 'package:agrobenta_mobile/features/transactions/state/transaction_detail_controller.dart';
import 'package:agrobenta_mobile/features/transactions/state/transaction_detail_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/inquiry_fakes.dart';
import '../../support/marketplace_fakes.dart';
import '../../support/messaging_fakes.dart';
import '../../support/notification_fakes.dart';
import '../../support/offer_fakes.dart';
import '../../support/seller_dashboard_fakes.dart';
import '../../support/seller_listing_fakes.dart';
import '../../support/seller_verification_fakes.dart';
import '../../support/transaction_fakes.dart';

/// Real-time reliability: background refreshes are coalesced (a burst never
/// stacks requests, and an event during a load is never dropped) and they
/// keep the content on screen.
///
/// Each controller below is driven over the same mock transport the app uses.
/// The [_Gate] holds responses for the refreshed path open, so a test can
/// deliver events while a request is genuinely in flight.

/// Holds responses open while [holding], then releases them one by one.
class _Gate {
  bool holding = false;
  final List<Completer<void>> _held = <Completer<void>>[];

  Future<http.Response> pass(http.Response Function() build) async {
    if (holding) {
      final Completer<void> completer = Completer<void>();
      _held.add(completer);
      await completer.future;
    }
    return build();
  }

  int get heldCount => _held.length;

  /// Releases the oldest held request and lets it settle.
  Future<void> releaseNext() async {
    _held.removeAt(0).complete();
    await pumpEventQueue();
  }

  /// Stops holding and releases everything still held.
  Future<void> releaseAll() async {
    holding = false;
    while (_held.isNotEmpty) {
      await releaseNext();
    }
  }
}

/// One controller under test.
class _Case {
  const _Case({
    required this.name,
    required this.build,
    required this.initialLoad,
    required this.isRefreshRequest,
    required this.event,
    required this.isBlocking,
  });

  final String name;

  /// Builds the controller over [handler]; responses for the refreshed path
  /// must go through the gate.
  final ChangeNotifier Function(
    Future<http.Response> Function(RecordedRequest) handler,
    List<RecordedRequest> recorded,
    Stream<RealtimeEvent> events,
  )
  build;

  final Future<void> Function(ChangeNotifier controller) initialLoad;

  /// Whether a recorded request is one refresh of the observed data.
  final bool Function(RecordedRequest request) isRefreshRequest;

  /// An event the controller answers with a refresh.
  final RealtimeEvent event;

  /// Whether the controller is showing its full-screen/blocking load state.
  final bool Function(ChangeNotifier controller) isBlocking;
}

http.Response _json(Object? data, {int status = 200}) => http.Response(
  jsonEncode(successEnvelope(data: data)),
  status,
  headers: const <String, String>{'content-type': 'application/json'},
);

final List<_Case> _cases = <_Case>[
  _Case(
    name: 'ChatController',
    build: (handler, recorded, events) => ChatController(
      buildMessagingRepository(
        FakeTokenStore('t'),
        handler,
        recorded: recorded,
      ),
      counterpartId: 3,
      currentUserId: 7,
      realtimeEvents: events,
    ),
    initialLoad: (c) => (c as ChatController).load(),
    isRefreshRequest: (r) => r.apiPath == '/conversations/3/messages',
    event: const RealtimeEvent(
      name: 'message.sent',
      data: <String, dynamic>{'sender_id': 3},
    ),
    isBlocking: (c) => (c as ChatController).state.status == ChatStatus.loading,
  ),
  _Case(
    name: 'ChatOffersController',
    build: (handler, recorded, events) => ChatOffersController(
      buildOfferRepository(FakeTokenStore('t'), handler, recorded: recorded),
      counterpartId: 3,
      realtimeEvents: events,
    ),
    initialLoad: (c) => (c as ChatOffersController).load(),
    isRefreshRequest: (r) => r.apiPath == '/offers',
    event: const RealtimeEvent(
      name: 'offer.created',
      data: <String, dynamic>{'buyer_id': 3, 'seller_id': 7},
    ),
    isBlocking: (c) =>
        (c as ChatOffersController).state.status == ChatOffersStatus.loading,
  ),
  _Case(
    name: 'NotificationsController',
    build: (handler, recorded, events) => NotificationsController(
      buildNotificationRepository(
        FakeTokenStore('t'),
        handler,
        recorded: recorded,
      ),
      realtimeEvents: events,
    ),
    initialLoad: (c) => (c as NotificationsController).load(),
    isRefreshRequest: (r) => r.apiPath == '/notifications',
    event: const RealtimeEvent(
      name: 'notification.created',
      data: <String, dynamic>{'type': 'listing'},
    ),
    isBlocking: (c) =>
        (c as NotificationsController).state.status ==
        NotificationsStatus.loading,
  ),
  _Case(
    name: 'ActiveInquiriesController',
    build: (handler, recorded, events) => ActiveInquiriesController(
      buildInquiryRepository(FakeTokenStore('t'), handler, recorded: recorded),
      role: 'buyer',
      realtimeEvents: events,
    ),
    initialLoad: (c) => (c as ActiveInquiriesController).load(),
    isRefreshRequest: (r) => r.apiPath == '/inquiries',
    event: const RealtimeEvent(
      name: 'inquiry.created',
      data: <String, dynamic>{},
    ),
    isBlocking: (c) =>
        (c as ActiveInquiriesController).state.status ==
        ActiveInquiriesStatus.loading,
  ),
  _Case(
    name: 'TransactionDetailController',
    build: (handler, recorded, events) => TransactionDetailController(
      buildTransactionRepository(
        FakeTokenStore('t'),
        handler,
        recorded: recorded,
      ),
      1,
      realtimeEvents: events,
    ),
    initialLoad: (c) => (c as TransactionDetailController).load(),
    isRefreshRequest: (r) => r.apiPath == '/transactions/1',
    event: const RealtimeEvent(
      name: 'transaction.updated',
      data: <String, dynamic>{'transaction_id': 1},
    ),
    isBlocking: (c) =>
        (c as TransactionDetailController).state.status ==
        TransactionDetailStatus.loading,
  ),
  _Case(
    name: 'SellerDashboardController',
    build: (handler, recorded, events) => SellerDashboardController(
      buildSellerDashboardRepository(
        FakeTokenStore('t'),
        handler,
        recorded: recorded,
      ),
      realtimeEvents: events,
    ),
    initialLoad: (c) => (c as SellerDashboardController).loadInitial(),
    isRefreshRequest: (r) => r.apiPath == '/seller/dashboard',
    event: const RealtimeEvent(
      name: 'inquiry.created',
      data: <String, dynamic>{},
    ),
    isBlocking: (c) =>
        (c as SellerDashboardController).state.status ==
        SellerDashboardStatus.loading,
  ),
  _Case(
    name: 'SellerVerificationController',
    build: (handler, recorded, events) => SellerVerificationController(
      buildSellerVerificationRepository(
        FakeTokenStore('t'),
        handler,
        recorded: recorded,
      ),
      realtimeEvents: events,
    ),
    initialLoad: (c) => (c as SellerVerificationController).load(),
    isRefreshRequest: (r) => r.apiPath == '/seller-verification/me',
    event: const RealtimeEvent(
      name: 'notification.created',
      data: <String, dynamic>{'type': 'seller_verification'},
    ),
    isBlocking: (c) =>
        (c as SellerVerificationController).state.status ==
        SellerVerificationUiStatus.loading,
  ),
  _Case(
    name: 'SellerListingController',
    build: (handler, recorded, events) => SellerListingController(
      buildSellerListingRepository(
        FakeTokenStore('t'),
        handler,
        recorded: recorded,
      ),
      realtimeEvents: events,
    ),
    initialLoad: (c) => (c as SellerListingController).loadInitial(),
    // The Active tab also fetches an `inactive` tail; one refresh is the
    // first-page request itself.
    isRefreshRequest: (r) =>
        r.apiPath == '/seller/listings' && r.query['status'] != 'inactive',
    event: const RealtimeEvent(
      name: 'notification.created',
      data: <String, dynamic>{'type': 'listing'},
    ),
    isBlocking: (c) =>
        (c as SellerListingController).state.status ==
        SellerListingStatus.loading,
  ),
  _Case(
    name: 'MarketplaceController',
    build: (handler, recorded, events) => buildMarketplaceController(
      FakeTokenStore('t'),
      handler,
      recorded: recorded,
      realtimeEvents: events,
    ),
    initialLoad: (c) => (c as MarketplaceController).loadInitial(),
    isRefreshRequest: (r) => r.apiPath == '/listings',
    event: const RealtimeEvent(
      name: 'listing.inventory.updated',
      data: <String, dynamic>{'listing_id': 1},
    ),
    isBlocking: (c) =>
        (c as MarketplaceController).state.status == MarketplaceStatus.loading,
  ),
];

/// A non-empty, successful response for every path the cases read.
http.Response _respond(RecordedRequest request) {
  final String path = request.apiPath;
  if (path == '/conversations/3/messages') {
    return messageThreadResponse(
      messages: <Map<String, dynamic>>[
        messageJson(senderId: 3, receiverId: 7, read: true),
      ],
    );
  }
  if (path == '/offers') {
    return offersResponse();
  }
  if (path == '/notifications/unread-count') {
    return unreadCountResponse(count: 1);
  }
  if (path == '/notifications') {
    return notificationsPageResponse(
      notifications: <Map<String, dynamic>>[notificationJson()],
    );
  }
  if (path == '/inquiries') {
    return inquiryListResponse();
  }
  if (path == '/transactions/1') {
    return transactionDetailResponse();
  }
  if (path == '/seller/dashboard') {
    return sellerDashboardResponse();
  }
  if (path == '/seller-verification/me') {
    return sellerVerificationResponse();
  }
  if (path == '/seller/listings') {
    return sellerListingListResponse(
      listings: <Map<String, dynamic>>[listingJson()],
    );
  }
  if (path == '/listings') {
    return marketplaceListResponse(
      listings: <Map<String, dynamic>>[listingJson()],
    );
  }
  return _json(null);
}

void main() {
  for (final _Case scenario in _cases) {
    group('${scenario.name} background refresh', () {
      late _Gate gate;
      late List<RecordedRequest> recorded;
      late StreamController<RealtimeEvent> events;
      late ChangeNotifier controller;
      late bool disposed;

      int refreshes() => recorded.where(scenario.isRefreshRequest).length;

      setUp(() {
        gate = _Gate();
        recorded = <RecordedRequest>[];
        events = StreamController<RealtimeEvent>.broadcast();
        disposed = false;
        controller = scenario.build(
          (RecordedRequest request) => scenario.isRefreshRequest(request)
              ? gate.pass(() => _respond(request))
              : Future<http.Response>.value(_respond(request)),
          recorded,
          events.stream,
        );
      });

      tearDown(() async {
        await gate.releaseAll();
        if (!disposed) {
          controller.dispose();
        }
        await events.close();
      });

      test(
        'a burst during a refresh yields exactly one trailing refresh',
        () async {
          await scenario.initialLoad(controller);
          expect(refreshes(), 1);

          gate.holding = true;
          events.add(scenario.event);
          await pumpEventQueue();
          expect(refreshes(), 2, reason: 'the first event refreshes');

          for (int i = 0; i < 5; i++) {
            events.add(scenario.event);
          }
          await pumpEventQueue();
          expect(refreshes(), 2, reason: 'no overlapping request mid-flight');

          await gate.releaseNext();
          expect(refreshes(), 3, reason: 'one trailing refresh for the burst');

          await gate.releaseAll();
          expect(refreshes(), 3, reason: 'settles; no refresh loop');
        },
      );

      test('an event during the initial load is answered after it', () async {
        gate.holding = true;
        final Future<void> first = scenario.initialLoad(controller);
        await pumpEventQueue();
        expect(refreshes(), 1);

        events.add(scenario.event);
        await pumpEventQueue();
        expect(refreshes(), 1, reason: 'never overlaps the initial load');

        await gate.releaseNext();
        await first;
        expect(refreshes(), 2, reason: 'the event is not dropped');
      });

      test(
        'a background refresh never shows the blocking load state',
        () async {
          await scenario.initialLoad(controller);
          final List<bool> blocking = <bool>[];
          controller.addListener(
            () => blocking.add(scenario.isBlocking(controller)),
          );

          events.add(scenario.event);
          await pumpEventQueue();

          expect(refreshes(), 2);
          expect(blocking, isNot(contains(true)));
        },
      );

      test('dispose cancels a pending trailing refresh', () async {
        await scenario.initialLoad(controller);
        gate.holding = true;
        events.add(scenario.event);
        events.add(scenario.event);
        await pumpEventQueue();
        expect(refreshes(), 2);

        controller.dispose();
        disposed = true;
        await gate.releaseAll();
        events.add(scenario.event);
        await pumpEventQueue();

        expect(refreshes(), 2, reason: 'nothing runs after dispose');
      });
    });
  }

  group('ChatController background refresh content', () {
    late List<RecordedRequest> recorded;
    late StreamController<RealtimeEvent> events;
    late List<Map<String, dynamic>> thread;
    late bool failThread;
    late bool visible;
    Completer<void>? holdSend;
    late ChatController controller;

    const RealtimeEvent incoming = RealtimeEvent(
      name: 'message.sent',
      data: <String, dynamic>{'sender_id': 3},
    );

    setUp(() {
      recorded = <RecordedRequest>[];
      events = StreamController<RealtimeEvent>.broadcast();
      thread = <Map<String, dynamic>>[
        messageJson(id: 1, senderId: 3, receiverId: 7, read: true),
      ];
      failThread = false;
      visible = true;
      holdSend = null;
      controller = ChatController(
        buildMessagingRepository(FakeTokenStore('t'), (
          RecordedRequest request,
        ) async {
          if (request.apiPath == '/conversations/3/messages') {
            return failThread
                ? _json(null, status: 500)
                : messageThreadResponse(messages: thread);
          }
          if (request.apiPath == '/messages') {
            await holdSend?.future;
            return _json(
              messageJson(id: 50, body: 'Hi', senderId: 7, receiverId: 3),
              status: 201,
            );
          }
          if (request.apiPath == '/conversations/3/read') {
            return threadReadResponse(updated: 1);
          }
          return _json(null);
        }, recorded: recorded),
        counterpartId: 3,
        currentUserId: 7,
        realtimeEvents: events.stream,
        isVisible: () => visible,
      );
    });

    tearDown(() async {
      controller.dispose();
      await events.close();
    });

    List<int> ids() => controller.state.messages.map((m) => m.id).toList();

    int readCalls() => recorded
        .where((RecordedRequest r) => r.apiPath == '/conversations/3/read')
        .length;

    test('a new message appears without dropping the thread', () async {
      await controller.load();
      thread = <Map<String, dynamic>>[
        messageJson(id: 2, senderId: 3, receiverId: 7, read: true),
        ...thread,
      ];

      events.add(incoming);
      await pumpEventQueue();

      expect(ids(), <int>[2, 1]);
      expect(controller.state.status, ChatStatus.ready);
    });

    test('a failed background refresh keeps the messages on screen', () async {
      await controller.load();
      failThread = true;

      events.add(incoming);
      await pumpEventQueue();

      expect(ids(), <int>[1]);
      expect(controller.state.status, ChatStatus.ready);
      expect(controller.state.errorMessage, isNull);
    });

    test('an unread incoming message is marked read while visible', () async {
      await controller.load();
      thread = <Map<String, dynamic>>[
        messageJson(id: 2, senderId: 3, receiverId: 7, read: false),
        ...thread,
      ];

      events.add(incoming);
      await pumpEventQueue();

      expect(readCalls(), 1);
      expect(controller.state.messages.first.read, isTrue);
    });

    test('a thread that is not visible is not marked read', () async {
      await controller.load();
      visible = false;
      thread = <Map<String, dynamic>>[
        messageJson(id: 2, senderId: 3, receiverId: 7, read: false),
        ...thread,
      ];

      events.add(incoming);
      await pumpEventQueue();

      expect(readCalls(), 0);
      expect(controller.state.messages.first.read, isFalse);
    });

    test('already-read messages cost no read request', () async {
      await controller.load();

      events.add(incoming);
      await pumpEventQueue();

      expect(readCalls(), 0);
    });

    test(
      'a refresh during a send keeps the bubble and never duplicates it',
      () async {
        await controller.load();
        holdSend = Completer<void>();
        final Future<bool> sending = controller.send('Hi');
        await pumpEventQueue();
        expect(ids().first, isNegative, reason: 'optimistic bubble shown');

        // The server already has the message when the refresh lands.
        thread = <Map<String, dynamic>>[
          messageJson(id: 50, body: 'Hi', senderId: 7, receiverId: 3),
          ...thread,
        ];
        events.add(incoming);
        await pumpEventQueue();
        expect(ids().first, isNegative, reason: 'still sending: bubble kept');
        expect(controller.state.isSending, isTrue);

        holdSend!.complete();
        expect(await sending, isTrue);

        expect(ids(), <int>[50, 1], reason: 'sent message exactly once');
      },
    );
  });

  group('NotificationsController background merge', () {
    test('keeps deeper pages and never shows a notification twice', () async {
      final StreamController<RealtimeEvent> events =
          StreamController<RealtimeEvent>.broadcast();
      List<Map<String, dynamic>> page1 = <Map<String, dynamic>>[
        notificationJson(id: 'b'),
        notificationJson(id: 'c'),
      ];
      final List<Map<String, dynamic>> page2 = <Map<String, dynamic>>[
        notificationJson(id: 'c'),
        notificationJson(id: 'd'),
      ];

      http.Response page(List<Map<String, dynamic>> items, int current) =>
          _json(<String, dynamic>{
            'notifications': items,
            'pagination': <String, dynamic>{
              'current_page': current,
              'last_page': 3,
              'per_page': 2,
              'total': 6,
            },
            'unread_count': 2,
          });

      final NotificationsController controller = NotificationsController(
        buildNotificationRepository(FakeTokenStore('t'), (
          RecordedRequest request,
        ) async {
          if (request.apiPath == '/notifications/unread-count') {
            return unreadCountResponse(count: 2);
          }
          return request.query['page'] == '2' ? page(page2, 2) : page(page1, 1);
        }),
        realtimeEvents: events.stream,
      );
      addTearDown(() async {
        controller.dispose();
        await events.close();
      });

      await controller.load();
      // A new notification arrives; then the user scrolls to page 2, where
      // the shift has pushed `c` (already on screen) onto that page.
      page1 = <Map<String, dynamic>>[
        notificationJson(id: 'a'),
        notificationJson(id: 'b'),
      ];
      await controller.loadMore();
      events.add(
        const RealtimeEvent(
          name: 'notification.created',
          data: <String, dynamic>{},
        ),
      );
      await pumpEventQueue();

      expect(controller.state.notifications.map((n) => n.id).toList(), <String>[
        'a',
        'b',
        'c',
        'd',
      ]);
      expect(controller.state.currentPage, 2, reason: 'scroll depth kept');
    });
  });

  // Reconnect/resume resynchronisation of the session-scoped lists. A list the
  // user never opened is not fetched (a buyer would otherwise spend a 403 on
  // seller listings every time the app resumes); a loaded one refreshes
  // silently.
  group('Session resync after reconnect or resume', () {
    Future<void> expectResync({
      required ChangeNotifier Function(
        Future<http.Response> Function(RecordedRequest) handler,
        List<RecordedRequest> recorded,
      )
      build,
      required Future<void> Function(ChangeNotifier) load,
      required void Function(ChangeNotifier) resync,
      required bool Function(RecordedRequest) isListRequest,
      required bool Function(ChangeNotifier) isBlocking,
    }) async {
      final List<RecordedRequest> recorded = <RecordedRequest>[];
      final ChangeNotifier controller = build(
        (RecordedRequest r) async => _respond(r),
        recorded,
      );
      addTearDown(controller.dispose);
      int requests() => recorded.where(isListRequest).length;

      resync(controller);
      await pumpEventQueue();
      expect(requests(), 0, reason: 'never loaded: nothing to resync');

      await load(controller);
      final List<bool> blocking = <bool>[];
      controller.addListener(() => blocking.add(isBlocking(controller)));
      resync(controller);
      await pumpEventQueue();
      expect(requests(), 2, reason: 'a loaded list resyncs once');
      expect(blocking, isNot(contains(true)));
    }

    test('notifications', () async {
      await expectResync(
        build: (handler, recorded) => NotificationsController(
          buildNotificationRepository(
            FakeTokenStore('t'),
            handler,
            recorded: recorded,
          ),
        ),
        load: (c) => (c as NotificationsController).load(),
        resync: (c) => (c as NotificationsController).refreshInBackground(),
        isListRequest: (r) => r.apiPath == '/notifications',
        isBlocking: (c) =>
            (c as NotificationsController).state.status ==
            NotificationsStatus.loading,
      );
    });

    test('marketplace', () async {
      await expectResync(
        build: (handler, recorded) => buildMarketplaceController(
          FakeTokenStore('t'),
          handler,
          recorded: recorded,
        ),
        load: (c) => (c as MarketplaceController).loadInitial(),
        resync: (c) => (c as MarketplaceController).refreshInBackground(),
        isListRequest: (r) => r.apiPath == '/listings',
        isBlocking: (c) =>
            (c as MarketplaceController).state.status ==
            MarketplaceStatus.loading,
      );
    });

    test('seller listings', () async {
      await expectResync(
        build: (handler, recorded) => SellerListingController(
          buildSellerListingRepository(
            FakeTokenStore('t'),
            handler,
            recorded: recorded,
          ),
        ),
        load: (c) => (c as SellerListingController).loadInitial(),
        resync: (c) => (c as SellerListingController).refreshInBackground(),
        isListRequest: (r) =>
            r.apiPath == '/seller/listings' && r.query['status'] != 'inactive',
        isBlocking: (c) =>
            (c as SellerListingController).state.status ==
            SellerListingStatus.loading,
      );
    });
  });
}
