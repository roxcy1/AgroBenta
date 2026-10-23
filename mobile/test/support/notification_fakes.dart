import 'dart:convert';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/repositories/notification_repository.dart';
import 'package:agrobenta_mobile/services/notification_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'auth_fakes.dart';

/// A `NotificationResource` payload exactly as the backend serialises one.
///
/// Field names and value spellings are copied from
/// `backend/app/Http/Resources/NotificationResource.php`; a test that passes
/// against this fixture is asserting against the real contract. `id` is a
/// UUID **string** — Laravel's notifications table, not an integer key.
Map<String, dynamic> notificationJson({
  Object? id = '0b7f6a3e-9c2d-4e8a-b1f6-2c9d8e5a7b41',
  String title = 'New inquiry',
  String body = 'Ana Reyes asked about Holstein Heifer.',
  String type = 'inquiries',
  String action = 'none',
  Object? actionId,
  bool read = false,
  Object? readAt,
  Object? createdAt = '2026-10-01T08:15:00.000000Z',
}) {
  return <String, dynamic>{
    'id': id,
    'title': title,
    'body': body,
    'type': type,
    'action': action,
    'action_id': actionId,
    'read': read,
    'read_at': readAt,
    'created_at': createdAt,
  };
}

const Map<String, String> _jsonHeaders = <String, String>{
  'content-type': 'application/json',
};

/// A successful `GET /notifications` page.
http.Response notificationsPageResponse({
  List<Map<String, dynamic>>? notifications,
  int total = 0,
  int unreadCount = 0,
  int statusCode = 200,
}) {
  final List<Map<String, dynamic>> list =
      notifications ?? <Map<String, dynamic>>[];
  return http.Response(
    jsonEncode(
      successEnvelope(
        data: <String, dynamic>{
          'notifications': list,
          'pagination': <String, dynamic>{
            'current_page': 1,
            'last_page': 1,
            'per_page': 15,
            'total': total == 0 ? list.length : total,
          },
          'unread_count': unreadCount,
        },
      ),
    ),
    statusCode,
    headers: _jsonHeaders,
  );
}

/// A successful `GET /notifications/unread-count`.
http.Response unreadCountResponse({int count = 0, int statusCode = 200}) {
  return http.Response(
    jsonEncode(successEnvelope(data: <String, dynamic>{'count': count})),
    statusCode,
    headers: _jsonHeaders,
  );
}

/// The notification stack over a mock transport, built through the same
/// [ApiClient] the app uses so envelope unwrapping and the bearer token are
/// exercised as production does.
NotificationRepository buildNotificationRepository(
  FakeTokenStore tokenStore,
  Future<http.Response> Function(RecordedRequest request) handler, {
  List<RecordedRequest>? recorded,
}) {
  final ApiClient client = ApiClient(
    tokenStorage: tokenStore,
    httpClient: MockClient((http.Request request) async {
      final RecordedRequest entry = RecordedRequest(request);
      recorded?.add(entry);
      return handler(entry);
    }),
  );
  return NotificationRepository(NotificationService(client));
}
