import 'dart:async';

import 'package:agrobenta_mobile/features/messaging/state/chat_controller.dart';
import 'package:agrobenta_mobile/features/messaging/state/conversations_controller.dart';
import 'package:agrobenta_mobile/features/messaging/state/messaging_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/auth_fakes.dart';
import '../../support/messaging_fakes.dart';

/// The inbox badge has no dedicated count endpoint, so it reconciles by
/// re-reading `/conversations`; an open thread re-reads its own messages.
/// Both must be silent (no `loading` state), stop in the background, and
/// catch up immediately on return.
void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;
  late StreamController<bool> visibility;

  setUp(() {
    tokenStore = FakeTokenStore('1|mobile-token');
    recorded = <RecordedRequest>[];
    visibility = StreamController<bool>.broadcast();
  });

  tearDown(() async {
    await visibility.close();
  });

  int requests(String path) =>
      recorded.where((RecordedRequest r) => r.apiPath == path).length;

  group('conversations polling', () {
    testWidgets('reconciles the unread badge without a manual refresh', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SizedBox.shrink());

      int unread = 3;
      final ConversationsController controller = ConversationsController(
        buildMessagingRepository(
          tokenStore,
          (RecordedRequest request) async => conversationsResponse(
            conversations: <Map<String, dynamic>>[
              conversationJson(unreadCount: unread),
            ],
          ),
          recorded: recorded,
        ),
        appVisibility: visibility.stream,
        pollInterval: const Duration(seconds: 30),
      );

      expect(controller.state.unreadCount(sellerMode: false), 0);

      // Capture every state the poll passes through: a silent reconciliation
      // must never report `loading`, which would blank the list.
      final List<ConversationsStatus> statuses = <ConversationsStatus>[];
      controller.addListener(() => statuses.add(controller.state.status));

      unread = 5;
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();

      expect(controller.state.unreadCount(sellerMode: true), 5);
      expect(controller.state.unreadCount(sellerMode: false), 5);
      expect(requests('/conversations'), 1);
      expect(statuses, isNot(contains(ConversationsStatus.loading)));
      expect(controller.state.status, ConversationsStatus.ready);

      // The binding asserts no timer outlives the test body.
      controller.dispose();
    });

    testWidgets('stops in the background and catches up on return', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SizedBox.shrink());

      final ConversationsController controller = ConversationsController(
        buildMessagingRepository(
          tokenStore,
          (RecordedRequest request) async => conversationsResponse(
            conversations: <Map<String, dynamic>>[
              conversationJson(unreadCount: 1),
            ],
          ),
          recorded: recorded,
        ),
        appVisibility: visibility.stream,
        pollInterval: const Duration(seconds: 30),
      );

      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      recorded.clear();

      visibility.add(false);
      await tester.pump();
      await tester.pump(const Duration(minutes: 1));
      await tester.pump();
      expect(recorded, isEmpty);

      visibility.add(true);
      await tester.pump();
      await tester.pump();
      expect(requests('/conversations'), 1);

      controller.dispose();
    });
  });

  group('open thread polling', () {
    testWidgets('re-reads the thread silently after an interval', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SizedBox.shrink());

      final ChatController controller = ChatController(
        buildMessagingRepository(
          tokenStore,
          (RecordedRequest request) async => messageThreadResponse(
            messages: <Map<String, dynamic>>[messageJson(id: 1)],
          ),
          recorded: recorded,
        ),
        counterpartId: 3,
        currentUserId: 7,
        appVisibility: visibility.stream,
        pollInterval: const Duration(seconds: 30),
      );

      await controller.load();
      expect(controller.state.status, ChatStatus.ready);
      recorded.clear();

      final List<ChatStatus> statuses = <ChatStatus>[];
      controller.addListener(() => statuses.add(controller.state.status));

      await tester.pump(const Duration(seconds: 30));
      await tester.pump();

      expect(requests('/conversations/3/messages'), 1);
      expect(controller.state.messages, hasLength(1));
      expect(controller.state.status, ChatStatus.ready);
      expect(
        statuses,
        isNot(contains(ChatStatus.loading)),
        reason: 'a poll must not blank the thread behind a spinner',
      );

      controller.dispose();
    });

    testWidgets('stops in the background and catches up on return', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SizedBox.shrink());

      final ChatController controller = ChatController(
        buildMessagingRepository(
          tokenStore,
          (RecordedRequest request) async => messageThreadResponse(
            messages: <Map<String, dynamic>>[messageJson(id: 1)],
          ),
          recorded: recorded,
        ),
        counterpartId: 3,
        currentUserId: 7,
        appVisibility: visibility.stream,
        pollInterval: const Duration(seconds: 30),
      );

      await controller.load();
      recorded.clear();

      visibility.add(false);
      await tester.pump();
      await tester.pump(const Duration(minutes: 1));
      await tester.pump();
      expect(recorded, isEmpty);

      visibility.add(true);
      await tester.pump();
      await tester.pump();
      expect(requests('/conversations/3/messages'), 1);

      controller.dispose();
    });
  });
}
