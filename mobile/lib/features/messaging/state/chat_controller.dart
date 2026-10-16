import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../models/message.dart';
import '../../../repositories/messaging_repository.dart';
import 'messaging_state.dart';

/// Presentation logic for one chat thread.
///
/// Per-screen, not session-scoped: each open chat owns one. Disposed when
/// the user leaves the screen, so the thread's messages do not outlive the
/// screen that showed them.
///
/// ## Optimistic send
///
/// [send] appends a placeholder message to the local list before the network
/// call completes, then replaces it with the server's response (or removes
/// it on failure). This makes the bubble appear instantly — a chat that
/// pauses for a round-trip feels broken — while keeping the source of truth
/// server-side: the placeholder has a temporary negative id and is discarded
/// the moment the real message lands.
class ChatController extends ChangeNotifier {
  /// The repository is a positional argument because Dart forbids a leading
  /// underscore in a named parameter, so `this._repository` cannot be used
  /// in the named form. A positional `this._repository` is the only way to
  /// make the analyzer happy without an `// ignore` comment, and the caller
  /// has exactly one repository to pass.
  ChatController(
    this._repository, {
    required this.counterpartId,
    required this.currentUserId,
    this.listingId,
  });

  final MessagingRepository _repository;

  /// The other user in the thread.
  final int counterpartId;

  /// The caller — passed in so the controller can render "mine vs theirs"
  /// without a second call to `/auth/me`.
  final int currentUserId;

  /// The listing this thread is about, if any.
  final int? listingId;

  ChatState _state = const ChatState();
  ChatState get state => _state;

  bool _disposed = false;
  bool _loading = false;
  int _generation = 0;

  /// A monotonic counter for optimistic placeholder ids. Negative so a
  /// placeholder can never collide with a real server id.
  int _placeholderCounter = 0;

  /// Loads the thread, unless one is already in flight.
  Future<void> load() async {
    if (_loading) {
      return;
    }
    _loading = true;

    final int generation = ++_generation;
    _set(
      _state.copyWith(
        status: ChatStatus.loading,
        clearError: true,
      ),
    );

    try {
      final List<Message> messages = await _repository.thread(
        counterpartId: counterpartId,
        listingId: listingId,
      );
      if (_disposed || generation != _generation) {
        return;
      }
      _set(
        _state.copyWith(
          status: ChatStatus.ready,
          messages: messages,
        ),
      );
    } on ApiException catch (error) {
      if (_disposed || generation != _generation) {
        return;
      }
      _set(
        _state.copyWith(
          status: ChatStatus.failed,
          errorMessage: error.message,
        ),
      );
    } on Object {
      if (_disposed || generation != _generation) {
        return;
      }
      _set(
        _state.copyWith(
          status: ChatStatus.failed,
          errorMessage: 'Something went wrong. Please try again.',
        ),
      );
    } finally {
      _loading = false;
    }
  }

  /// Refreshes the thread — used after marking read.
  Future<void> refresh() => load();

  /// Sends a message. Returns `true` on success.
  ///
  /// The bubble is added optimistically so the user sees their text
  /// immediately. On failure, the placeholder is removed and the error
  /// surfaces via [ChatState.sendErrorMessage].
  Future<bool> send(String body) async {
    final String trimmed = body.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    if (_state.isSending) {
      return false;
    }

    final int placeholderId = --_placeholderCounter;
    final Message placeholder = Message(
      id: placeholderId,
      body: trimmed,
      senderId: currentUserId,
      receiverId: counterpartId,
      listingId: listingId,
      read: false,
      readAt: null,
      createdAt: DateTime.now(),
      sender: const ChatUser(id: 0, name: '', avatarUrl: null),
      receiver: const ChatUser(id: 0, name: '', avatarUrl: null),
    );

    _set(
      _state.copyWith(
        status: ChatStatus.sending,
        messages: <Message>[placeholder, ..._state.messages],
        clearSendError: true,
      ),
    );

    try {
      final Message sent = await _repository.send(
        receiverId: counterpartId,
        body: trimmed,
        listingId: listingId,
      );
      if (_disposed) {
        return false;
      }
      _set(
        _state.copyWith(
          status: ChatStatus.ready,
          messages: <Message>[
            sent,
            ..._state.messages.where((Message m) => m.id != placeholderId),
          ],
        ),
      );
      return true;
    } on ApiException catch (error) {
      if (_disposed) {
        return false;
      }
      _set(
        _state.copyWith(
          status: ChatStatus.ready,
          messages: _state.messages
              .where((Message m) => m.id != placeholderId)
              .toList(growable: false),
          sendErrorMessage: error.message,
        ),
      );
      return false;
    } on Object {
      if (_disposed) {
        return false;
      }
      _set(
        _state.copyWith(
          status: ChatStatus.ready,
          messages: _state.messages
              .where((Message m) => m.id != placeholderId)
              .toList(growable: false),
          sendErrorMessage: 'Something went wrong. Please try again.',
        ),
      );
      return false;
    }
  }

  /// Marks every unread message in this thread as read.
  Future<void> markRead() async {
    try {
      await _repository.markThreadRead(
        counterpartId: counterpartId,
        listingId: listingId,
      );
      if (_disposed) {
        return;
      }
      // Update local state so the "unread" dots on bubbles disappear.
      final List<Message> updated = _state.messages.map((Message m) {
        if (m.receiverId == currentUserId && !m.read) {
          return Message(
            id: m.id,
            body: m.body,
            senderId: m.senderId,
            receiverId: m.receiverId,
            listingId: m.listingId,
            read: true,
            readAt: DateTime.now(),
            createdAt: m.createdAt,
            sender: m.sender,
            receiver: m.receiver,
          );
        }
        return m;
      }).toList(growable: false);
      _set(_state.copyWith(messages: updated));
    } on Object {
      // Silent: the next load fixes the truth.
    }
  }

  /// Clears the send error so a snackbar is not shown twice.
  void clearSendError() {
    if (_state.sendErrorMessage == null) {
      return;
    }
    _set(_state.copyWith(clearSendError: true));
  }

  void _set(ChatState next) {
    if (_disposed) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}