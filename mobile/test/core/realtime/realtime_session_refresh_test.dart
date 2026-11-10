import 'dart:async';

import 'package:agrobenta_mobile/core/realtime/realtime_event.dart';
import 'package:agrobenta_mobile/features/notifications/state/notifications_controller.dart';
import 'package:agrobenta_mobile/features/seller_listings/state/seller_listing_controller.dart';
import 'package:agrobenta_mobile/features/seller_verification/state/seller_verification_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/notification_fakes.dart';
import '../../support/seller_listing_fakes.dart';
import '../../support/seller_verification_fakes.dart';

/// Phase 2 — notification list and approval/rejection status refresh.
///
/// The controllers subscribe to the decoded events themselves, so each test
/// drives them over the same mock transport the app uses and observes the
/// refresh as a real request. Scoping is checked by the negative cases: an
/// unrelated event or notification type must not spend a request.
void main() {
  group('NotificationsController real-time', () {
    late FakeTokenStore tokenStore;
    late List<RecordedRequest> recorded;
    late StreamController<RealtimeEvent> events;
    late NotificationsController controller;

    setUp(() async {
      tokenStore = FakeTokenStore()..token = 'stored-token';
      recorded = <RecordedRequest>[];
      events = StreamController<RealtimeEvent>.broadcast();
      controller = NotificationsController(
        buildNotificationRepository(
          tokenStore,
          (RecordedRequest request) async =>
              request.apiPath == '/notifications/unread-count'
                  ? unreadCountResponse(count: 1)
                  : notificationsPageResponse(),
          recorded: recorded,
        ),
        realtimeEvents: events.stream,
      );

      // Put the controller past its initial-load guard, then count only the
      // requests caused by the events below. This also pins the fix that lets
      // the first load run (otherwise the inbox never leaves its spinner).
      await controller.load();
      expect(recorded, isNotEmpty, reason: 'the first load must fetch a page');
      recorded.clear();
    });

    tearDown(() async {
      controller.dispose();
      await events.close();
    });

    int count(String path) =>
        recorded.where((RecordedRequest r) => r.apiPath == path).length;

    test('any event refreshes the unread badge', () async {
      events.add(const RealtimeEvent(name: 'message.sent', data: {}));
      await pumpEventQueue();

      expect(count('/notifications/unread-count'), 1);
      expect(count('/notifications'), 0);
    });

    test('notification.created reloads the list as well as the badge',
        () async {
      events.add(const RealtimeEvent(
        name: 'notification.created',
        data: <String, dynamic>{'type': 'listing'},
      ));
      await pumpEventQueue();

      expect(count('/notifications/unread-count'), 1);
      expect(count('/notifications'), 1);
    });
  });

  group('SellerVerificationController real-time', () {
    late FakeTokenStore tokenStore;
    late List<RecordedRequest> recorded;
    late StreamController<RealtimeEvent> events;
    late SellerVerificationController controller;

    setUp(() async {
      tokenStore = FakeTokenStore()..token = 'stored-token';
      recorded = <RecordedRequest>[];
      events = StreamController<RealtimeEvent>.broadcast();
      controller = SellerVerificationController(
        buildSellerVerificationRepository(
          tokenStore,
          (RecordedRequest request) async => sellerVerificationResponse(),
          recorded: recorded,
        ),
        realtimeEvents: events.stream,
      );

      await controller.load();
      recorded.clear();
    });

    tearDown(() async {
      controller.dispose();
      await events.close();
    });

    test('a seller_verification notification reloads the status', () async {
      events.add(const RealtimeEvent(
        name: 'notification.created',
        data: <String, dynamic>{'type': 'seller_verification'},
      ));
      await pumpEventQueue();

      expect(recorded.where((r) => r.apiPath == '/seller-verification/me'), hasLength(1));
    });

    test('a listing notification does not reload the status', () async {
      events.add(const RealtimeEvent(
        name: 'notification.created',
        data: <String, dynamic>{'type': 'listing'},
      ));
      await pumpEventQueue();

      expect(recorded, isEmpty);
    });
  });

  group('SellerListingController real-time', () {
    late FakeTokenStore tokenStore;
    late List<RecordedRequest> recorded;
    late StreamController<RealtimeEvent> events;
    late SellerListingController controller;

    setUp(() async {
      tokenStore = FakeTokenStore()..token = 'stored-token';
      recorded = <RecordedRequest>[];
      events = StreamController<RealtimeEvent>.broadcast();
      controller = SellerListingController(
        buildSellerListingRepository(
          tokenStore,
          (RecordedRequest request) async => sellerListingListResponse(),
          recorded: recorded,
        ),
        realtimeEvents: events.stream,
      );

      await controller.loadInitial();
      recorded.clear();
    });

    tearDown(() async {
      controller.dispose();
      await events.close();
    });

    test('a listing notification reloads the seller listings', () async {
      events.add(const RealtimeEvent(
        name: 'notification.created',
        data: <String, dynamic>{'type': 'listing'},
      ));
      await pumpEventQueue();

      expect(recorded.where((r) => r.apiPath == '/seller/listings'), hasLength(1));
    });

    test('a seller_verification notification does not reload listings',
        () async {
      events.add(const RealtimeEvent(
        name: 'notification.created',
        data: <String, dynamic>{'type': 'seller_verification'},
      ));
      await pumpEventQueue();

      expect(recorded, isEmpty);
    });
  });
}
