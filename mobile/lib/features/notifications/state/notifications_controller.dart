import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../models/app_notification.dart';
import '../../../repositories/notification_repository.dart';
import '../../../services/notification_service.dart';
import 'notifications_state.dart';

/// Presentation logic for the caller's notifications.
///
/// ## Session-scoped
///
/// One instance lives for the whole signed-in session, held in
/// [NotificationsScope] above `MaterialApp`. That is what lets the Home
/// AppBar's bell badge read the same state the Notifications screen shows —
/// a per-screen controller would need its own badge count and could disagree
/// with the list.
///
/// ## Pagination
///
/// Page 1 loads on `load()`; `loadMore()` appends. A "load more" is only
/// attempted when the server has said there is another page, so a short
/// list never fires a wasted request.
///
/// ## Optimistic read
///
/// `markRead` and `markAllRead` update the local list first, then call the
/// server. A failure leaves the optimistic state in place — the next `load()`
/// corrects it. The alternative, waiting for the round-trip, would make the
/// badge flicker.
class NotificationsController extends ChangeNotifier {
  NotificationsController(this._repository);

  final NotificationRepository _repository;

  NotificationsState _state = const NotificationsState();
  NotificationsState get state => _state;

  bool _disposed = false;
  bool _loadingMore = false;
  int _generation = 0;

  /// Loads page 1, unless one is already in flight.
  ///
  /// A [filter] argument switches the active chip and reloads from page 1.
  /// Passing `null` explicitly clears the filter (shows all); passing no
  /// argument at all keeps the current filter. The distinction matters
  /// because "All" is a valid filter value that is *not* a filter.
  Future<void> load({String? filter, bool changeFilter = false}) async {
    if (_state.isInitialLoad && !changeFilter) {
      return;
    }

    final String? nextFilter = changeFilter ? filter : _state.activeFilter;
    final int generation = ++_generation;

    _set(
      _state.copyWith(
        status: NotificationsStatus.loading,
        notifications: const <AppNotification>[],
        activeFilter: nextFilter,
        clearActiveFilter: changeFilter && nextFilter == null,
        currentPage: 1,
        clearError: true,
        clearLoadMoreError: true,
      ),
    );

    try {
      final NotificationPage page = await _repository.list(
        type: nextFilter,
        page: 1,
      );
      if (_disposed || generation != _generation) {
        return;
      }
      _set(
        _state.copyWith(
          status: NotificationsStatus.ready,
          notifications: page.notifications,
          unreadCount: page.unreadCount,
          currentPage: page.currentPage,
          lastPage: page.lastPage,
          total: page.total,
        ),
      );
    } on ApiException catch (error) {
      if (_disposed || generation != _generation) {
        return;
      }
      _set(
        _state.copyWith(
          status: NotificationsStatus.failed,
          errorMessage: error.message,
        ),
      );
    } on Object {
      if (_disposed || generation != _generation) {
        return;
      }
      _set(
        _state.copyWith(
          status: NotificationsStatus.failed,
          errorMessage: 'Something went wrong. Please try again.',
        ),
      );
    }
  }

  /// Requests the next page.
  Future<void> loadMore() async {
    if (_loadingMore || !_state.hasMorePages) {
      return;
    }
    if (_state.status != NotificationsStatus.ready) {
      return;
    }

    _loadingMore = true;
    _set(
      _state.copyWith(
        status: NotificationsStatus.loadingMore,
        clearLoadMoreError: true,
      ),
    );

    try {
      final NotificationPage page = await _repository.list(
        type: _state.activeFilter,
        page: _state.currentPage + 1,
      );
      if (_disposed) {
        return;
      }
      _set(
        _state.copyWith(
          status: NotificationsStatus.ready,
          notifications: <AppNotification>[
            ..._state.notifications,
            ...page.notifications,
          ],
          unreadCount: page.unreadCount,
          currentPage: page.currentPage,
          lastPage: page.lastPage,
          total: page.total,
        ),
      );
    } on ApiException catch (error) {
      if (_disposed) {
        return;
      }
      _set(
        _state.copyWith(
          status: NotificationsStatus.ready,
          loadMoreErrorMessage: error.message,
        ),
      );
    } on Object {
      if (_disposed) {
        return;
      }
      _set(
        _state.copyWith(
          status: NotificationsStatus.ready,
          loadMoreErrorMessage: 'Something went wrong. Please try again.',
        ),
      );
    } finally {
      _loadingMore = false;
    }
  }

  /// Switches the active filter chip. `null` selects "All".
  Future<void> applyFilter(String? filter) =>
      load(filter: filter, changeFilter: true);

  /// Re-queries page 1 while keeping what is on screen.
  Future<void> refresh() => load(changeFilter: false);

  /// Marks one notification as read.
  ///
  /// Optimistic: flips the local copy and decrements the count before the
  /// request. A failure is not surfaced to the user — the next `refresh()`
  /// corrects the truth, and this is a background housekeeping call rather
  /// than a user-visible action.
  Future<void> markRead(String id) async {
    final AppNotification? target = _firstWhereOrNull(
      _state.notifications,
      (AppNotification n) => n.id == id,
    );
    if (target == null || target.read) {
      return;
    }

    final List<AppNotification> updated = _state.notifications
        .map((AppNotification n) => n.id == id ? n.markRead() : n)
        .toList(growable: false);

    final int nextUnread = (_state.unreadCount - 1).clamp(0, 1 << 30);
    _set(_state.copyWith(notifications: updated, unreadCount: nextUnread));

    try {
      await _repository.markRead(id);
    } on Object {
      // Silent: the next refresh fixes the truth.
    }
  }

  /// Marks every notification as read.
  ///
  /// Same optimistic shape as [markRead], applied to the whole list.
  Future<void> markAllRead() async {
    if (_state.unreadCount == 0) {
      return;
    }

    final List<AppNotification> updated = _state.notifications
        .map((AppNotification n) => n.read ? n : n.markRead())
        .toList(growable: false);

    _set(_state.copyWith(notifications: updated, unreadCount: 0));

    try {
      await _repository.markAllRead();
    } on Object {
      // Silent: the next refresh fixes the truth.
    }
  }

  /// The single source of truth for the badge count.
  ///
  /// A cheap call — the mobile bell polls this rather than the full list.
  Future<void> refreshUnreadCount() async {
    try {
      final int count = await _repository.unreadCount();
      if (_disposed) {
        return;
      }
      _set(_state.copyWith(unreadCount: count));
    } on Object {
      // Silent: a stale badge is better than a crash.
    }
  }

  /// Dart's `List.firstWhere` with an orElse that returns null — inlined
  /// because the package has no equivalent that returns a nullable.
  static AppNotification? _firstWhereOrNull(
    List<AppNotification> items,
    bool Function(AppNotification) test,
  ) {
    for (final AppNotification item in items) {
      if (test(item)) {
        return item;
      }
    }
    return null;
  }

  void _set(NotificationsState next) {
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