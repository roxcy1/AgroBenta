import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/realtime/realtime_event.dart';
import '../../../models/conversation.dart';
import '../../../repositories/messaging_repository.dart';
import 'messaging_state.dart';

/// Presentation logic for the caller's inbox.
///
/// Session-scoped: one instance lives for the whole signed-in session, held
/// in [MessagingScope] above `MaterialApp`. That is what makes the unread
/// badge in the buyer shell possible — the shell reads the same controller
/// the Conversations screen reads, and both rebuild together.
///
/// ## Why there is no pagination
///
/// The backend returns the entire conversation list in one response. A user
/// has at most a handful of active threads (bounded by distinct counterparts
/// they have messaged), so paginating an inbox is worse than just sending
/// everything. If the list ever grows past a threshold, this controller is
/// the one place that changes.
///
/// ## Polling
///
/// The unread badge is derived from this list — there is no separate
/// messages-count endpoint — so the badge can only reconcile by re-reading
/// the inbox. When [appVisibility] is supplied, that happens on a light timer
/// while the app is in the foreground, and pauses in the background. The poll
/// is silent: it never sets the `loading` status, so it cannot blank the
/// screen or flash a spinner, and it shares the generation counter with
/// `load()` so concurrent responses cannot interleave.
class ConversationsController extends ChangeNotifier {
  ConversationsController(
    this._repository, {
    this.realtimeEvents,
    this.appVisibility,
    this.pollInterval = const Duration(seconds: 30),
  }) {
    _realtimeSubscription = realtimeEvents?.listen(_onRealtimeEvent);
    _visibilitySubscription = appVisibility?.listen(_onVisibilityChanged);
    _startPolling();
  }

  final MessagingRepository _repository;

  /// The session's decoded events. Message/inquiry/offer events move a
  /// conversation preview (last message, unread count, latest offer).
  final Stream<RealtimeEvent>? realtimeEvents;

  /// Foreground state. Polling only exists when this is supplied.
  final Stream<bool>? appVisibility;

  /// How often the inbox is re-read while the app is in the foreground.
  final Duration pollInterval;

  StreamSubscription<RealtimeEvent>? _realtimeSubscription;
  StreamSubscription<bool>? _visibilitySubscription;
  Timer? _pollTimer;
  bool _polling = false;

  ConversationsState _state = const ConversationsState();
  ConversationsState get state => _state;

  bool _disposed = false;
  bool _loading = false;
  int _generation = 0;

  /// Loads the inbox, unless one is already in flight.
  Future<void> load() async {
    if (_loading) {
      return;
    }
    _loading = true;

    final int generation = ++_generation;
    _set(
      _state.copyWith(
        status: ConversationsStatus.loading,
        clearError: true,
        clearRefreshError: true,
      ),
    );

    try {
      final List<Conversation> conversations = await _repository
          .conversations();
      if (_disposed || generation != _generation) {
        return;
      }
      _set(
        _state.copyWith(
          status: ConversationsStatus.ready,
          conversations: conversations,
        ),
      );
    } on ApiException catch (error) {
      if (_disposed || generation != _generation) {
        return;
      }
      _set(
        _state.copyWith(
          status: ConversationsStatus.failed,
          errorMessage: error.message,
        ),
      );
    } on Object {
      if (_disposed || generation != _generation) {
        return;
      }
      _set(
        _state.copyWith(
          status: ConversationsStatus.failed,
          errorMessage: 'Something went wrong. Please try again.',
        ),
      );
    } finally {
      _loading = false;
    }
  }

  /// Re-fetches the inbox while keeping what is on screen.
  Future<void> refresh() async {
    if (_state.conversations.isEmpty) {
      return load();
    }

    final int generation = ++_generation;
    _set(_state.copyWith(clearRefreshError: true));

    try {
      final List<Conversation> conversations = await _repository
          .conversations();
      if (_disposed || generation != _generation) {
        return;
      }
      _set(
        _state.copyWith(
          status: ConversationsStatus.ready,
          conversations: conversations,
        ),
      );
    } on ApiException catch (error) {
      if (_disposed || generation != _generation) {
        return;
      }
      _set(_state.copyWith(refreshErrorMessage: error.message));
    } on Object {
      if (_disposed || generation != _generation) {
        return;
      }
      _set(
        _state.copyWith(
          refreshErrorMessage: 'Something went wrong. Please try again.',
        ),
      );
    }
  }

  /// Marks a thread as read and updates the local list optimistically.
  ///
  /// Called when the user opens a chat. The server also has to know — the
  /// unread count is enforced server-side — but showing the badge as zero
  /// immediately is the right behaviour: the user is looking at the thread
  /// right now, so it *is* read.
  Future<void> markRead(int counterpartId) async {
    // Optimistic: flip the local state before the request.
    final List<Conversation> updated = _state.conversations
        .map((Conversation c) {
          if (c.counterpart.id == counterpartId && c.hasUnread) {
            return c.copyWith(unreadCount: 0);
          }
          return c;
        })
        .toList(growable: false);

    _set(_state.copyWith(conversations: updated));

    try {
      await _repository.markThreadRead(counterpartId: counterpartId);
    } on Object {
      // A failure leaves the local badge at zero — the next `load()` fixes
      // the truth. Not surfaced to the user: this is a background housekeeping
      // call, not a user-visible action.
    }
  }

  /// Updates the inbox search text. Pure view filtering — no request.
  void setSearch(String query) {
    if (query == _state.query) {
      return;
    }
    _set(_state.copyWith(query: query));
  }

  /// Switches the category filter. Pure view filtering — no request.
  void setFilter(InboxFilter filter) {
    if (filter == _state.filter) {
      return;
    }
    _set(_state.copyWith(filter: filter));
  }

  void _set(ConversationsState next) {
    if (_disposed) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  /// Message/inquiry/offer events move a conversation preview, so re-fetch the
  /// inbox. Other events (transactions, notifications) leave it unchanged.
  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.name == 'message.sent' ||
        event.name == 'inquiry.created' ||
        event.name == 'offer.created' ||
        event.name == 'offer.updated') {
      unawaited(refresh());
    }
  }

  /// Reconciles the inbox without touching what is on screen.
  ///
  /// Deliberately not `refresh()`: that delegates to `load()` for an empty
  /// inbox, which sets `loading` and would flash a spinner every interval.
  /// A poll is a background correction; on failure the previous state stays
  /// exactly as it was.
  Future<void> _poll() async {
    if (_disposed || _polling || _loading) {
      return;
    }
    _polling = true;
    final int generation = ++_generation;

    try {
      final List<Conversation> conversations = await _repository
          .conversations();
      if (_disposed || generation != _generation) {
        return;
      }
      _set(
        _state.copyWith(
          status: ConversationsStatus.ready,
          conversations: conversations,
          clearError: true,
          clearRefreshError: true,
        ),
      );
    } on Object {
      // Silent: a stale inbox is better than an error the user did not ask
      // for. Pull-to-refresh still surfaces failures explicitly.
    } finally {
      _polling = false;
    }
  }

  void _startPolling() {
    if (appVisibility == null || _disposed) {
      return;
    }
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      pollInterval,
      (Timer _) => unawaited(_poll()),
    );
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _onVisibilityChanged(bool visible) {
    if (visible) {
      unawaited(_poll());
      _startPolling();
    } else {
      _stopPolling();
    }
  }

  @override
  void dispose() {
    _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    _visibilitySubscription?.cancel();
    _visibilitySubscription = null;
    _stopPolling();
    _disposed = true;
    super.dispose();
  }
}
