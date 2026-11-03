import 'package:agrobenta_mobile/features/messaging/state/messaging_state.dart';
import 'package:agrobenta_mobile/models/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/messaging_fakes.dart';

void main() {
  Conversation conversation({
    required int counterpartId,
    required List<String> roles,
    required int unread,
  }) {
    return Conversation.fromJson(
      conversationJson(
        counterpart: chatUserJson(id: counterpartId, name: 'U$counterpartId'),
        roles: roles,
        unreadCount: unread,
      ),
    );
  }

  final List<Conversation> conversations = <Conversation>[
    conversation(counterpartId: 1, roles: <String>['buyer'], unread: 2),
    conversation(counterpartId: 2, roles: <String>['buyer'], unread: 3),
    conversation(counterpartId: 3, roles: <String>['seller'], unread: 4),
    conversation(
      counterpartId: 4,
      roles: <String>['buyer', 'seller'],
      unread: 1,
    ),
    conversation(counterpartId: 5, roles: <String>[], unread: 1),
  ];

  final ConversationsState state = ConversationsState(
    status: ConversationsStatus.ready,
    conversations: conversations,
  );

  group('unread counts are messages, scoped to the account mode', () {
    test('Buyer Mode sums unread messages of buyer-visible threads', () {
      // 2 + 3 + 1 (both sides) + 1 (unclassified) — messages, not threads.
      expect(state.unreadCount(sellerMode: false), 7);
    });

    test('Seller Mode sums its own threads', () {
      expect(state.unreadCount(sellerMode: true), 6);
    });

    test('a thread the caller trades both ways counts in both modes', () {
      expect(state.hasUnread(sellerMode: false), isTrue);
      expect(state.hasUnread(sellerMode: true), isTrue);
    });

    test('an unclassified thread is never hidden', () {
      final List<Conversation> buyer = state.visibleConversations(
        sellerMode: false,
      );
      final List<Conversation> seller = state.visibleConversations(
        sellerMode: true,
      );

      expect(buyer.map((Conversation c) => c.counterpart.id), contains(5));
      expect(seller.map((Conversation c) => c.counterpart.id), contains(5));
    });

    test('mode filtering does not change the underlying conversations', () {
      expect(state.conversations, hasLength(5));
      expect(state.visibleConversations(sellerMode: false), hasLength(4));
      expect(state.visibleConversations(sellerMode: true), hasLength(3));
    });
  });
}
