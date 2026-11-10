import 'dart:async';

import 'package:agrobenta_mobile/core/realtime/realtime_event.dart';
import 'package:agrobenta_mobile/features/messaging/state/chat_controller.dart';
import 'package:agrobenta_mobile/features/offers/state/chat_offers_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/auth_fakes.dart';
import '../../support/messaging_fakes.dart';
import '../../support/offer_fakes.dart';

/// Phase 1 — live refresh for the open chat thread and the open offer panel.
///
/// The controllers are driven over the same mock transport the app uses, so a
/// refresh is observed as a real `GET` and the event filtering is exercised
/// against the payloads the backend actually broadcasts.
void main() {
  group('ChatController real-time refresh', () {
    late FakeTokenStore tokenStore;
    late List<RecordedRequest> recorded;
    late StreamController<RealtimeEvent> events;
    late ChatController? controller;

    setUp(() {
      tokenStore = FakeTokenStore()..token = 'stored-token';
      recorded = <RecordedRequest>[];
      events = StreamController<RealtimeEvent>.broadcast();
      controller = ChatController(
        buildMessagingRepository(
          tokenStore,
          (RecordedRequest request) async => messageThreadResponse(),
          recorded: recorded,
        ),
        counterpartId: 3,
        currentUserId: 7,
        realtimeEvents: events.stream,
      );
    });

    tearDown(() async {
      controller?.dispose();
      await events.close();
    });

    int threadRequests() => recorded
        .where((RecordedRequest r) => r.apiPath == '/conversations/3/messages')
        .length;

    test('a message from the counterpart refreshes the open thread', () async {
      await controller!.load();
      expect(threadRequests(), 1);

      events.add(const RealtimeEvent(
        name: 'message.sent',
        data: <String, dynamic>{'sender_id': 3},
      ));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(threadRequests(), 2);
    });

    test('a message from another user does not refresh', () async {
      await controller!.load();

      events.add(const RealtimeEvent(
        name: 'message.sent',
        data: <String, dynamic>{'sender_id': 99},
      ));
      await Future<void>.delayed(Duration.zero);

      expect(threadRequests(), 1);
    });

    test('a non-message event does not refresh the thread', () async {
      await controller!.load();

      events.add(const RealtimeEvent(
        name: 'offer.created',
        data: <String, dynamic>{'buyer_id': 3, 'seller_id': 7},
      ));
      await Future<void>.delayed(Duration.zero);

      expect(threadRequests(), 1);
    });

    test('disposing cancels the subscription (no leak)', () async {
      await controller!.load();
      controller!.dispose();
      controller = null;

      events.add(const RealtimeEvent(
        name: 'message.sent',
        data: <String, dynamic>{'sender_id': 3},
      ));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(threadRequests(), 1);
    });
  });

  group('ChatOffersController real-time refresh', () {
    late FakeTokenStore tokenStore;
    late List<RecordedRequest> recorded;
    late StreamController<RealtimeEvent> events;
    late ChatOffersController? controller;

    setUp(() {
      tokenStore = FakeTokenStore()..token = 'stored-token';
      recorded = <RecordedRequest>[];
      events = StreamController<RealtimeEvent>.broadcast();
      controller = ChatOffersController(
        buildOfferRepository(
          tokenStore,
          (RecordedRequest request) async => offersResponse(),
          recorded: recorded,
        ),
        counterpartId: 3,
        realtimeEvents: events.stream,
      );
    });

    tearDown(() async {
      controller?.dispose();
      await events.close();
    });

    int offerRequests() => recorded
        .where((RecordedRequest r) => r.apiPath == '/offers')
        .length;

    test('an offer involving the counterpart refreshes the panel', () async {
      await controller!.load();
      expect(offerRequests(), 1);

      events.add(const RealtimeEvent(
        name: 'offer.created',
        data: <String, dynamic>{'buyer_id': 3, 'seller_id': 7},
      ));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(offerRequests(), 2);
    });

    test('an offer update involving the counterpart refreshes the panel',
        () async {
      await controller!.load();
      expect(offerRequests(), 1);

      events.add(const RealtimeEvent(
        name: 'offer.updated',
        data: <String, dynamic>{'buyer_id': 3, 'seller_id': 7},
      ));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(offerRequests(), 2);
    });

    test('an offer for another pair does not refresh', () async {
      await controller!.load();

      events.add(const RealtimeEvent(
        name: 'offer.updated',
        data: <String, dynamic>{'buyer_id': 8, 'seller_id': 9},
      ));
      await Future<void>.delayed(Duration.zero);

      expect(offerRequests(), 1);
    });

    test('a non-offer event does not refresh the panel', () async {
      await controller!.load();

      events.add(const RealtimeEvent(
        name: 'message.sent',
        data: <String, dynamic>{'sender_id': 3},
      ));
      await Future<void>.delayed(Duration.zero);

      expect(offerRequests(), 1);
    });

    test('disposing cancels the subscription (no leak)', () async {
      await controller!.load();
      controller!.dispose();
      controller = null;

      events.add(const RealtimeEvent(
        name: 'offer.created',
        data: <String, dynamic>{'buyer_id': 3, 'seller_id': 7},
      ));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(offerRequests(), 1);
    });
  });
}
