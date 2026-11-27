import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/realtime/realtime_event.dart';
import '../../../core/realtime/refresh_coalescer.dart';
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
    this.messageListingId,
    this.realtimeEvents,
    this.connection,
    this.isVisible,
  }) {
    _realtimeSubscription = realtimeEvents?.listen(_onRealtimeEvent);
    _connectionSubscription = connection?.listen(_onConnectionChanged);
  }

  final MessagingRepository _repository;

  /// Whether the thread is actually on screen (its route is the top route and
  /// the app is in the foreground). When it is, messages that arrive in the
  /// background refresh are marked read, because the user is looking at them.
  /// `null` means the thread is always treated as visible.
  final bool Function()? isVisible;

  /// Background refreshes requested by real-time events and reconnects. They
  /// keep the thread on screen and never overlap [load].
  late final RefreshCoalescer _backgroundRefresh = RefreshCoalescer(
    _refreshInBackground,
    isBusy: () => _loading,
  );

  /// The session's decoded events. When supplied, a message from the
  /// counterpart refreshes this open thread without a manual pull.
  final Stream<RealtimeEvent>? realtimeEvents;

  /// Connection changes; a reconnect re-fetches to recover missed messages.
  final Stream<bool>? connection;

  StreamSubscription<RealtimeEvent>? _realtimeSubscription;
  StreamSubscription<bool>? _connectionSubscription;

  /// The other user in the thread.
  final int counterpartId;

  /// The caller — passed in so the controller can render "mine vs theirs"
  /// without a second call to `/auth/me`.
  final int currentUserId;

  /// The listing this thread is filtered to, if any.
  final int? listingId;

  /// The listing to tag outgoing messages with, when the caller opened this
  /// chat from a listing. Kept separate from [listingId] so the thread can show
  /// the whole buyer–seller history even when the conversation started
  /// elsewhere and a reply has no `listing_id` of its own.
  final int? messageListingId;

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
    _set(_state.copyWith(status: ChatStatus.loading, clearError: true));
    try {
      await _fetch(silent: false);
    } finally {
      _loading = false;
      _backgroundRefresh.settled();
    }
  }

  /// Refreshes the thread — used after marking read.
  Future<void> refresh() => load();

  /// Re-fetches the thread without the full-screen loading state.
  ///
  /// The messages on screen stay put until the response replaces them, and a
  /// failure leaves them untouched (the next event or reconnect retries).
  /// Newly received messages are marked read while the thread is visible.
  Future<void> _refreshInBackground() => _fetch(silent: true);

  /// The one read behind [load] and [_refreshInBackground].
  ///
  /// Optimistic bubbles whose send is still in flight are kept on top, so a
  /// response landing mid-send cannot make the user's text vanish. A [silent]
  /// read leaves the thread untouched on failure.
  Future<void> _fetch({required bool silent}) async {
    final int generation = ++_generation;
    bool stale() => _disposed || generation != _generation;
    try {
      final List<Message> messages = await _repository.thread(
        counterpartId: counterpartId,
        listingId: listingId,
      );
      if (stale()) {
        return;
      }
      final List<Message> pendingSends = _state.messages
          .where((Message m) => m.id < 0)
          .toList(growable: false);
      _set(
        _state.copyWith(
          status: _state.isSending ? ChatStatus.sending : ChatStatus.ready,
          messages: <Message>[...pendingSends, ...messages],
          clearError: true,
        ),
      );
      // On open the screen marks the thread read itself; this covers messages
      // that arrive while it stays open.
      if (silent &&
          messages.any(_isUnreadIncoming) &&
          (isVisible?.call() ?? true)) {
        await markRead();
      }
    } on ApiException catch (error) {
      if (!stale() && !silent) {
        _set(
          _state.copyWith(
            status: ChatStatus.failed,
            errorMessage: error.message,
          ),
        );
      }
    } on Object {
      if (!stale() && !silent) {
        _set(
          _state.copyWith(
            status: ChatStatus.failed,
            errorMessage: 'Something went wrong. Please try again.',
          ),
        );
      }
    }
  }

  bool _isUnreadIncoming(Message m) => m.receiverId == currentUserId && !m.read;

  /// A new message from the counterpart refreshes the open thread. Scoped to
  /// the counterpart so an unrelated conversation's event does not re-fetch it.
  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.name == 'message.sent' &&
        event.data['sender_id'] == counterpartId) {
      _backgroundRefresh.request();
    }
  }

  /// A reconnect may have missed messages while the socket was down.
  void _onConnectionChanged(bool connected) {
    if (connected) {
      _backgroundRefresh.request();
    }
  }

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
      listingId: messageListingId ?? listingId,
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
        listingId: messageListingId ?? listingId,
      );
      if (_disposed) {
        return false;
      }
      _set(
        _state.copyWith(
          status: ChatStatus.ready,
          // A background refresh may already have fetched the sent message,
          // so drop it by id as well as the placeholder: never shown twice.
          messages: <Message>[
            sent,
            ..._state.messages.where(
              (Message m) => m.id != placeholderId && m.id != sent.id,
            ),
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
      final List<Message> updated = _state.messages
          .map((Message m) {
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
          })
          .toList(growable: false);
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
    _backgroundRefresh.dispose();
    _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _disposed = true;
    super.dispose();
  }
}
