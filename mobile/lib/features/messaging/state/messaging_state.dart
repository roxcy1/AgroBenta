import 'package:flutter/foundation.dart';

import '../../../models/conversation.dart';
import '../../../models/message.dart';

/// The lifecycle states for the conversations list.
enum ConversationsStatus {
  initial,
  loading,
  ready,
  failed,
}

/// The lifecycle states for one chat thread.
enum ChatStatus {
  initial,
  loading,
  ready,
  failed,
  sending,
}

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
  });

  final ConversationsStatus status;
  final List<Conversation> conversations;
  final String? errorMessage;
  final String? refreshErrorMessage;

  /// Whether any conversation has unread messages — used for the tab badge.
  int get totalUnread =>
      conversations.fold<int>(0, (int sum, Conversation c) => sum + c.unreadCount);

  bool get hasUnread => totalUnread > 0;

  bool get isInitialLoad =>
      status == ConversationsStatus.initial || status == ConversationsStatus.loading;

  ConversationsState copyWith({
    ConversationsStatus? status,
    List<Conversation>? conversations,
    String? errorMessage,
    String? refreshErrorMessage,
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