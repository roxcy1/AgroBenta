import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
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
class ConversationsController extends ChangeNotifier {
  ConversationsController(this._repository);

  final MessagingRepository _repository;

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
      final List<Conversation> conversations = await _repository.conversations();
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
      final List<Conversation> conversations = await _repository.conversations();
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
    final List<Conversation> updated = _state.conversations.map((Conversation c) {
      if (c.counterpart.id == counterpartId && c.hasUnread) {
        return Conversation(
          counterpart: c.counterpart,
          listingId: c.listingId,
          listingTitle: c.listingTitle,
          lastMessage: c.lastMessage,
          lastMessageAt: c.lastMessageAt,
          unreadCount: 0,
        );
      }
      return c;
    }).toList(growable: false);

    _set(_state.copyWith(conversations: updated));

    try {
      await _repository.markThreadRead(counterpartId: counterpartId);
    } on Object {
      // A failure leaves the local badge at zero — the next `load()` fixes
      // the truth. Not surfaced to the user: this is a background housekeeping
      // call, not a user-visible action.
    }
  }

  void _set(ConversationsState next) {
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