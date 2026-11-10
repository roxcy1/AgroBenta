import 'dart:async';

import 'package:agrobenta_mobile/core/realtime/realtime_event.dart';
import 'package:agrobenta_mobile/features/messaging/state/chat_controller.dart';
import 'package:agrobenta_mobile/features/transactions/state/transaction_detail_controller.dart';
import 'package:agrobenta_mobile/features/transactions/state/transactions_controller.dart';
import 'package:agrobenta_mobile/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/auth_fakes.dart';
import '../../support/messaging_fakes.dart';
import '../../support/transaction_fakes.dart';

/// Phase 4 — reconnect reconciliation and listener cleanup.
///
/// A reconnect must re-fetch the open screen (events missed while the socket
/// was down), and a disposed controller must stop listening (no refresh, no
/// leak).
void main() {
  group('reconnect reconciliation', () {
    test('ChatController refreshes on reconnect and stops after dispose',
        () async {
      final FakeTokenStore tokenStore = FakeTokenStore()
        ..token = 'stored-token';
      final List<RecordedRequest> recorded = <RecordedRequest>[];
      final StreamController<RealtimeEvent> events =
          StreamController<RealtimeEvent>.broadcast();
      final StreamController<bool> connection =
          StreamController<bool>.broadcast();
      addTearDown(() async {
        await events.close();
        await connection.close();
      });

      final ChatController controller = ChatController(
        buildMessagingRepository(
          tokenStore,
          (RecordedRequest request) async => messageThreadResponse(),
          recorded: recorded,
        ),
        counterpartId: 3,
        currentUserId: 7,
        realtimeEvents: events.stream,
        connection: connection.stream,
      );

      await controller.load();
      recorded.clear();

      connection.add(true);
      await pumpEventQueue();
      expect(
        recorded.where((r) => r.apiPath == '/conversations/3/messages'),
        hasLength(1),
      );

      recorded.clear();
      connection.add(false);
      await pumpEventQueue();
      expect(recorded, isEmpty);

      controller.dispose();
      connection.add(true);
      await pumpEventQueue();
      expect(recorded, isEmpty, reason: 'a disposed controller must not listen');
    });

    test('TransactionsController refreshes on reconnect', () async {
      final FakeTokenStore tokenStore = FakeTokenStore()
        ..token = 'stored-token';
      final List<RecordedRequest> recorded = <RecordedRequest>[];
      final StreamController<bool> connection =
          StreamController<bool>.broadcast();
      addTearDown(connection.close);

      final TransactionsController controller = TransactionsController(
        buildTransactionRepository(
          tokenStore,
          (RecordedRequest request) async => transactionListResponse(),
          recorded: recorded,
        ),
        null,
        role: TransactionRole.buyer,
        connection: connection.stream,
      );
      addTearDown(controller.dispose);

      await controller.loadInitial();
      recorded.clear();

      connection.add(true);
      await pumpEventQueue();

      expect(recorded.where((r) => r.apiPath == '/transactions'), hasLength(1));
    });

    test('TransactionDetailController reloads on reconnect', () async {
      final FakeTokenStore tokenStore = FakeTokenStore()
        ..token = 'stored-token';
      final List<RecordedRequest> recorded = <RecordedRequest>[];
      final StreamController<bool> connection =
          StreamController<bool>.broadcast();
      addTearDown(connection.close);

      final TransactionDetailController controller = TransactionDetailController(
        buildTransactionRepository(
          tokenStore,
          (RecordedRequest request) async => transactionDetailResponse(),
          recorded: recorded,
        ),
        1,
        connection: connection.stream,
      );
      addTearDown(controller.dispose);

      await controller.load();
      recorded.clear();

      connection.add(true);
      await pumpEventQueue();

      expect(recorded.where((r) => r.apiPath == '/transactions/1'), hasLength(1));
    });
  });
}
