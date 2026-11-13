import 'dart:async';
import 'dart:convert';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/core/push/push_messaging.dart';
import 'package:agrobenta_mobile/repositories/device_repository.dart';
import 'package:agrobenta_mobile/services/device_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'auth_fakes.dart';

/// A scriptable [PushMessaging] that records what the app asked of it.
class FakePushMessaging implements PushMessaging {
  FakePushMessaging({this.token = 'fcm-token-1'});

  /// The token the next permission request returns; null means refused.
  String? token;

  /// Completes the next token request when set, so a test can hold it open.
  Completer<String?>? pendingTokenRequest;

  final List<String> calls = <String>[];
  final StreamController<String> refreshes =
      StreamController<String>.broadcast();
  final StreamController<Map<String, String>> opened =
      StreamController<Map<String, String>>.broadcast();

  @override
  Future<String?> requestPermissionAndGetToken() async {
    calls.add('getToken');
    final Completer<String?>? pending = pendingTokenRequest;
    if (pending != null) {
      pendingTokenRequest = null;
      return pending.future;
    }
    return token;
  }

  @override
  Stream<String> get onTokenRefresh => refreshes.stream;

  @override
  Stream<Map<String, String>> get openedNotifications => opened.stream;

  @override
  Future<void> deleteToken() async {
    calls.add('deleteToken');
  }

  Future<void> close() async {
    await refreshes.close();
    await opened.close();
  }
}

http.Response deviceRegisteredResponse({int statusCode = 200}) =>
    http.Response(
      jsonEncode(<String, dynamic>{
        'success': statusCode < 300,
        'message': 'Device registered for notifications.',
      }),
      statusCode,
      headers: const <String, String>{'content-type': 'application/json'},
    );

DeviceService buildDeviceService(
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
  return DeviceService(client);
}

DeviceRepository buildDeviceRepository(
  FakeTokenStore tokenStore,
  Future<http.Response> Function(RecordedRequest request) handler, {
  List<RecordedRequest>? recorded,
}) => DeviceRepository(
  buildDeviceService(tokenStore, handler, recorded: recorded),
);
