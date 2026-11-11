import 'dart:async';

import 'package:agrobenta_mobile/core/realtime/realtime_event.dart';
import 'package:agrobenta_mobile/features/inquiries/state/active_inquiries_controller.dart';
import 'package:agrobenta_mobile/features/seller_dashboard/state/seller_dashboard_controller.dart';
import 'package:agrobenta_mobile/features/transactions/state/transaction_detail_controller.dart';
import 'package:agrobenta_mobile/features/transactions/state/transactions_controller.dart';
import 'package:agrobenta_mobile/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/auth_fakes.dart';
import '../../support/inquiry_fakes.dart';
import '../../support/seller_dashboard_fakes.dart';
import '../../support/transaction_fakes.dart';

/// Phase 3 — transaction, inquiry and dashboard refresh.
///
/// Each controller is driven over the app's mock transport; the tests assert the
/// positive refresh and, crucially, the negative scope: an unrelated event or a
/// different transaction must not spend a request.
void main() {
  group('TransactionsController real-time', () {
    late FakeTokenStore tokenStore;
    late List<RecordedRequest> recorded;
    late StreamController<RealtimeEvent> events;
    late TransactionsController controller;

    setUp(() async {
      tokenStore = FakeTokenStore()..token = 'stored-token';
      recorded = <RecordedRequest>[];
      events = StreamController<RealtimeEvent>.broadcast();
      controller = TransactionsController(
        buildTransactionRepository(
          tokenStore,
          (RecordedRequest request) async => transactionListResponse(),
          recorded: recorded,
        ),
        null,
        role: TransactionRole.buyer,
        realtimeEvents: events.stream,
      );
      await controller.loadInitial();
      recorded.clear();
    });

    tearDown(() async {
      controller.dispose();
      await events.close();
    });

    test('a transaction event refreshes the list', () async {
      events.add(const RealtimeEvent(name: 'transaction.created', data: {}));
      await pumpEventQueue();

      expect(recorded.where((r) => r.apiPath == '/transactions'), hasLength(1));
    });

    test('an unrelated event does not refresh the list', () async {
      events.add(const RealtimeEvent(name: 'message.sent', data: {}));
      await pumpEventQueue();

      expect(recorded, isEmpty);
    });
  });

  group('TransactionDetailController real-time', () {
    late FakeTokenStore tokenStore;
    late List<RecordedRequest> recorded;
    late StreamController<RealtimeEvent> events;
    late TransactionDetailController controller;

    setUp(() async {
      tokenStore = FakeTokenStore()..token = 'stored-token';
      recorded = <RecordedRequest>[];
      events = StreamController<RealtimeEvent>.broadcast();
      controller = TransactionDetailController(
        buildTransactionRepository(
          tokenStore,
          (RecordedRequest request) async => transactionDetailResponse(),
          recorded: recorded,
        ),
        1,
        realtimeEvents: events.stream,
      );
      await controller.load();
      recorded.clear();
    });

    tearDown(() async {
      controller.dispose();
      await events.close();
    });

    test('a change to this transaction re-loads the detail', () async {
      events.add(const RealtimeEvent(
        name: 'transaction.updated',
        data: <String, dynamic>{'transaction_id': 1},
      ));
      await pumpEventQueue();

      expect(recorded.where((r) => r.apiPath == '/transactions/1'), hasLength(1));
    });

    test('a change to another transaction does not re-load', () async {
      events.add(const RealtimeEvent(
        name: 'transaction.updated',
        data: <String, dynamic>{'transaction_id': 2},
      ));
      await pumpEventQueue();

      expect(recorded, isEmpty);
    });
  });

  group('ActiveInquiriesController real-time', () {
    late FakeTokenStore tokenStore;
    late List<RecordedRequest> recorded;
    late StreamController<RealtimeEvent> events;
    late ActiveInquiriesController controller;

    setUp(() async {
      tokenStore = FakeTokenStore()..token = 'stored-token';
      recorded = <RecordedRequest>[];
      events = StreamController<RealtimeEvent>.broadcast();
      controller = ActiveInquiriesController(
        buildInquiryRepository(
          tokenStore,
          (RecordedRequest request) async => inquiryListResponse(),
          recorded: recorded,
        ),
        role: 'seller',
        realtimeEvents: events.stream,
      );
      await controller.load();
      recorded.clear();
    });

    tearDown(() async {
      controller.dispose();
      await events.close();
    });

    test('an inquiry or offer event refreshes the tab', () async {
      events.add(const RealtimeEvent(name: 'inquiry.created', data: {}));
      await pumpEventQueue();
      expect(recorded.where((r) => r.apiPath == '/inquiries'), hasLength(1));

      events.add(const RealtimeEvent(name: 'offer.updated', data: {}));
      await pumpEventQueue();
      expect(recorded.where((r) => r.apiPath == '/inquiries'), hasLength(2));
    });

    test('a transaction event does not refresh the inquiries tab', () async {
      events.add(const RealtimeEvent(name: 'transaction.updated', data: {}));
      await pumpEventQueue();

      expect(recorded, isEmpty);
    });
  });

  group('SellerDashboardController real-time', () {
    late FakeTokenStore tokenStore;
    late List<RecordedRequest> recorded;
    late StreamController<RealtimeEvent> events;
    late SellerDashboardController controller;

    setUp(() async {
      tokenStore = FakeTokenStore()..token = 'stored-token';
      recorded = <RecordedRequest>[];
      events = StreamController<RealtimeEvent>.broadcast();
      controller = SellerDashboardController(
        buildSellerDashboardRepository(
          tokenStore,
          (RecordedRequest request) async => sellerDashboardResponse(),
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

    int dashboardRequests() =>
        recorded.where((r) => r.apiPath == '/seller/dashboard').length;

    test('inquiry, transaction and listing-decision events refresh counts',
        () async {
      events.add(const RealtimeEvent(name: 'inquiry.created', data: {}));
      await pumpEventQueue();
      expect(dashboardRequests(), 1);

      events.add(const RealtimeEvent(name: 'transaction.updated', data: {}));
      await pumpEventQueue();
      expect(dashboardRequests(), 2);

      events.add(const RealtimeEvent(
        name: 'notification.created',
        data: <String, dynamic>{'type': 'listing'},
      ));
      await pumpEventQueue();
      expect(dashboardRequests(), 3);
    });

    test('a non-listing notification does not refresh the dashboard', () async {
      events.add(const RealtimeEvent(
        name: 'notification.created',
        data: <String, dynamic>{'type': 'seller_verification'},
      ));
      await pumpEventQueue();

      expect(dashboardRequests(), 0);
    });
  });
}
