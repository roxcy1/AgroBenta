import '../core/constants/api_constants.dart';
import '../core/network/api_client.dart';
import '../models/app_notification.dart';

/// A page of notifications, as the backend returns it.
///
/// Kept as a small value object rather than reusing `Pagination` from the
/// marketplace because the notification endpoint bundles `unread_count` in
/// the same response, and that value is not on the generic `Pagination` type.
/// Modeling the exact shape here is one fewer place to hunt if it changes.
class NotificationPage {
  const NotificationPage({
    required this.notifications,
    required this.currentPage,
    required this.lastPage,
    required this.perPage,
    required this.total,
    required this.unreadCount,
  });

  final List<AppNotification> notifications;
  final int currentPage;
  final int lastPage;
  final int perPage;
  final int total;
  final int unreadCount;

  bool get hasMorePages => currentPage < lastPage;
}

/// The notification transport.
///
/// Thin on purpose: every request goes through [ApiClient], which owns the
/// bearer token, the envelope unwrapping and the `401` handling. The service's
/// only jobs are to know the paths and to shape responses into models.
class NotificationService {
  const NotificationService(this._client);

  final ApiClient _client;

  /// `GET /notifications` — the caller's inbox.
  Future<NotificationPage> list({
    String? type,
    bool? unread,
    int page = 1,
    int? perPage,
  }) {
    return _client.get<NotificationPage>(
      NotificationEndpoints.list,
      query: <String, dynamic>{
        'type': ?type,
        'unread': ?(unread == null ? null : (unread ? '1' : '0')),
        'page': page,
        'per_page': ?perPage,
      },
      parse: (Object? data) {
        final Map<String, dynamic> map = _asMap(data);
        final List<dynamic> raw =
            (map['notifications'] as List<dynamic>?) ?? const <dynamic>[];
        final Map<String, dynamic> pagination =
            (map['pagination'] as Map<String, dynamic>?) ??
                const <String, dynamic>{};
        final int unreadCount =
            (map['unread_count'] as num?)?.toInt() ?? 0;

        return NotificationPage(
          notifications: raw
              .whereType<Map<String, dynamic>>()
              .map(AppNotification.fromJson)
              .toList(growable: false),
          currentPage: (pagination['current_page'] as num?)?.toInt() ?? 1,
          lastPage: (pagination['last_page'] as num?)?.toInt() ?? 1,
          perPage: (pagination['per_page'] as num?)?.toInt() ?? 15,
          total: (pagination['total'] as num?)?.toInt() ?? 0,
          unreadCount: unreadCount,
        );
      },
    );
  }

  /// `GET /notifications/unread-count` — the badge count.
  Future<int> unreadCount() {
    return _client.get<int>(
      NotificationEndpoints.unreadCount,
      parse: (Object? data) {
        final Map<String, dynamic> map = _asMap(data);
        return (map['count'] as num?)?.toInt() ?? 0;
      },
    );
  }

  /// `PATCH /notifications/{id}/read` — mark one as read.
  Future<AppNotification> markRead(String id) {
    return _client.patch<AppNotification>(
      NotificationEndpoints.read(id),
      parse: (Object? data) => AppNotification.fromJson(_asMap(data)),
    );
  }

  /// `POST /notifications/read-all` — mark every unread as read.
  ///
  /// Returns nothing: the server's response is a message + new count, and
  /// the caller only needs to know the request succeeded.
  Future<void> markAllRead() {
    return _client.post<void>(
      NotificationEndpoints.readAll,
      parse: (_) {},
    );
  }

  static Map<String, dynamic> _asMap(Object? data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return data.cast<String, dynamic>();
    }
    throw const FormatException('Expected a JSON object.');
  }
}