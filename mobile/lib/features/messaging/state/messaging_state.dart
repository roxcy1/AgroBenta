import 'package:flutter/foundation.dart';

import '../../../models/conversation.dart';
import '../../../models/message.dart';

/// The inbox category filters.
///
/// Only filters the conversation data can actually decide exist here. There
/// is no category column: a conversation's sole classification is whether it
/// is tied to a listing (`listing_id`), which is exactly what
/// [InboxFilter.inquiries] selects. "Transactions" is deliberately absent — the
/// API models no transaction-message relationship (GAP-11), so the screen
/// renders that chip disabled. "Notifications" is not a filter at all:
/// notifications have their own destination, which the screen links to.
enum InboxFilter { all, inquiries }

/// The lifecycle states for the conversations list.
enum ConversationsStatus { initial, loading, ready, failed }

/// The lifecycle states for one chat thread.
enum ChatStatus { initial, loading, ready, failed, sending }

/// The immutable state of the conversations list.
///
/// One controller owns one of these. A session-scoped controller means the
/// inbox is loaded once and survives tab switches.
@immutable
class ConversationsState {
  const ConversationsState({
    this.status = ConversationsStatus.initial,
    this.conversations = const <Conversation>[],
    this.errorMessage,
    this.refreshErrorMessage,
    this.query = '',
    this.filter = InboxFilter.all,
  });

  final ConversationsStatus status;
  final List<Conversation> conversations;
  final String? errorMessage;
  final String? refreshErrorMessage;

  /// The inbox search text, kept in state so it survives tab switches.
  final String query;

  /// The selected category filter.
  final InboxFilter filter;

  /// Whether any conversation has unread messages — used for the tab badge.
  int get totalUnread => conversations.fold<int>(
    0,
    (int sum, Conversation c) => sum + c.unreadCount,
  );

  bool get hasUnread => totalUnread > 0;

  bool get isInitialLoad =>
      status == ConversationsStatus.initial ||
      status == ConversationsStatus.loading;

  /// What the list actually renders: [filter] first, then a case-insensitive
  /// local search over the participant name, the listing title and the last
  /// message preview. Local because the API offers no conversation search and
  /// the whole inbox is one response (Messages design §3.2).
  List<Conversation> get visibleConversations {
    final String needle = query.trim().toLowerCase();
    return conversations
        .where((Conversation conversation) {
          if (filter == InboxFilter.inquiries &&
              conversation.listingId == null) {
            return false;
          }
          if (needle.isEmpty) {
            return true;
          }
          return conversation.counterpart.name.toLowerCase().contains(needle) ||
              (conversation.listingTitle?.toLowerCase().contains(needle) ??
                  false) ||
              conversation.lastMessage.toLowerCase().contains(needle);
        })
        .toList(growable: false);
  }

  ConversationsState copyWith({
    ConversationsStatus? status,
    List<Conversation>? conversations,
    String? errorMessage,
    String? refreshErrorMessage,
    String? query,
    InboxFilter? filter,
    bool clearError = false,
    bool clearRefreshError = false,
  }) {
    return ConversationsState(
      status: status ?? this.status,
      conversations: conversations ?? this.conversations,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      refreshErrorMessage: clearRefreshError
          ? null
          : (refreshErrorMessage ?? this.refreshErrorMessage),
      query: query ?? this.query,
      filter: filter ?? this.filter,
    );
  }
}

/// The immutable state of one chat thread.
@immutable
class ChatState {
  const ChatState({
    this.status = ChatStatus.initial,
    this.messages = const <Message>[],
    this.errorMessage,
    this.sendErrorMessage,
  });

  final ChatStatus status;

  /// Newest first — the same order the API returns.
  final List<Message> messages;

  /// A load failure.
  final String? errorMessage;

  /// A send failure, shown as a snackbar.
  final String? sendErrorMessage;

  bool get isLoading =>
      status == ChatStatus.initial || status == ChatStatus.loading;

  bool get isSending => status == ChatStatus.sending;

  ChatState copyWith({
    ChatStatus? status,
    List<Message>? messages,
    String? errorMessage,
    String? sendErrorMessage,
    bool clearError = false,
    bool clearSendError = false,
  }) {
    return ChatState(
      status: status ?? this.status,
      messages: messages ?? this.messages,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      sendErrorMessage: clearSendError
          ? null
          : (sendErrorMessage ?? this.sendErrorMessage),
    );
  }
}
