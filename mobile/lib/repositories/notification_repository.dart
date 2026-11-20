import '../core/constants/api_constants.dart';
import '../models/app_notification.dart';
import '../models/notification_preferences.dart';
import '../services/notification_service.dart';

/// Orchestration for notifications.
///
/// Thin, like every other repository in this app: the transport sits behind
/// [NotificationService], so the only policy worth owning here is the page
/// size. The server caps `per_page` at 50 with a `422`, and that limit is a
/// fact about the API rather than about any screen. Clamping it here means no
/// widget can discover the cap by provoking an error.
class NotificationRepository {
  const NotificationRepository(this._service);

  final NotificationService _service;

  /// Fetches one page of the caller's notifications.
  Future<NotificationPage> list({
    String? type,
    bool? unread,
    int page = 1,
    int? perPage,
  }) {
    return _service.list(
      type: type,
      unread: unread,
      page: page < 1 ? 1 : page,
      perPage: _clampPerPage(perPage),
    );
  }

  /// The unread count, for the badge.
  Future<int> unreadCount() => _service.unreadCount();

  /// Marks one notification as read.
  Future<AppNotification> markRead(String id) => _service.markRead(id);

  /// Marks every unread notification as read.
  Future<void> markAllRead() => _service.markAllRead();

  /// The caller's push switches.
  Future<NotificationPreferences> preferences() => _service.preferences();

  /// Switches one category's phone push on or off.
  Future<NotificationPreferences> updatePreference(
    NotificationCategory category, {
    required bool enabled,
  }) => _service.updatePreference(category, enabled: enabled);

  static int _clampPerPage(int? perPage) {
    final int requested = perPage ?? NotificationEndpoints.defaultPerPage;
    if (requested < 1) {
      return 1;
    }
    if (requested > NotificationEndpoints.maxPerPage) {
      return NotificationEndpoints.maxPerPage;
    }
    return requested;
  }
}
