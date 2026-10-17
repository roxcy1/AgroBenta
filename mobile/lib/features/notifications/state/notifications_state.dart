import 'package:flutter/foundation.dart';

import '../../../models/app_notification.dart';

/// The lifecycle states for the notifications list.
enum NotificationsStatus {
  initial,
  loading,
  ready,
  failed,
  loadingMore,
}

/// The immutable state of the notifications feature.
///
/// ## Why `unreadCount` is separate from `notifications.length`
///
/// The list is paginated and filterable — the count reflects the *total*
/// unread across every notification, not just the ones currently on screen.
/// The server returns both in the same response, and the badge reads the
/// count while the list reads the items.
@immutable
class NotificationsState {
  const NotificationsState({
    this.status = NotificationsStatus.initial,
    this.notifications = const <AppNotification>[],
    this.unreadCount = 0,
    this.activeFilter,
    this.currentPage = 1,
    this.lastPage = 1,
    this.total = 0,
    this.errorMessage,
    this.loadMoreErrorMessage,
  });

  final NotificationsStatus status;
  final List<AppNotification> notifications;

  /// The total unread count across every notification — the badge value.
  final int unreadCount;

  /// The active filter chip, or `null` for "All".
  final String? activeFilter;

  final int currentPage;
  final int lastPage;
  final int total;

  /// A load failure (first page).
  final String? errorMessage;

  /// A load-more failure.
  final String? loadMoreErrorMessage;

  bool get isLoadingMore => status == NotificationsStatus.loadingMore;

  bool get isInitialLoad =>
      status == NotificationsStatus.initial ||
      status == NotificationsStatus.loading;

  bool get hasMorePages => currentPage < lastPage;

  bool get isEmpty => notifications.isEmpty;

  NotificationsState copyWith({
    NotificationsStatus? status,
    List<AppNotification>? notifications,
    int? unreadCount,
    String? activeFilter,
    bool clearActiveFilter = false,
    int? currentPage,
    int? lastPage,
    int? total,
    String? errorMessage,
    String? loadMoreErrorMessage,
    bool clearError = false,
    bool clearLoadMoreError = false,
  }) {
    return NotificationsState(
      status: status ?? this.status,
      notifications: notifications ?? this.notifications,
      unreadCount: unreadCount ?? this.unreadCount,
      activeFilter:
          clearActiveFilter ? null : (activeFilter ?? this.activeFilter),
      currentPage: currentPage ?? this.currentPage,
      lastPage: lastPage ?? this.lastPage,
      total: total ?? this.total,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      loadMoreErrorMessage: clearLoadMoreError
          ? null
          : (loadMoreErrorMessage ?? this.loadMoreErrorMessage),
    );
  }
}