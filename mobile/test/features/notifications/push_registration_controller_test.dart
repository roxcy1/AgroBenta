import 'dart:async';

import 'package:agrobenta_mobile/features/notifications/state/push_registration_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/auth_fakes.dart';
import '../../support/push_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;
  late FakePushMessaging messaging;
  late int statusCode;
  late PushRegistrationController controller;

  List<String> registeredTokens() => recorded
      .where((RecordedRequest r) => r.apiPath == '/devices')
      .map((RecordedRequest r) => r.body['token'] as String)
      .toList();

  setUp(() {
    tokenStore = FakeTokenStore('1|mobile-token');
    recorded = <RecordedRequest>[];
    messaging = FakePushMessaging();
    statusCode = 200;
    controller = PushRegistrationController(
      messaging,
      buildDeviceRepository(
        tokenStore,
        (_) async => deviceRegisteredResponse(statusCode: statusCode),
        recorded: recorded,
      ),
    );
  });

  tearDown(() async {
    controller.dispose();
    await messaging.close();
  });

  test('starting a session registers the phone token', () async {
    await controller.start();

    expect(registeredTokens(), <String>['fcm-token-1']);
  });

  test('nothing is sent when the user refuses notifications', () async {
    messaging.token = null;

    await controller.start();

    expect(recorded, isEmpty);
  });

  test('a refreshed token is registered too', () async {
    await controller.start();
    messaging.refreshes.add('fcm-token-2');
    await pumpEventQueue();

    expect(registeredTokens(), <String>['fcm-token-1', 'fcm-token-2']);
  });

  test('ending the session deletes the token and stops listening', () async {
    await controller.start();
    await controller.stop();
    messaging.refreshes.add('fcm-token-2');
    await pumpEventQueue();

    expect(messaging.calls.last, 'deleteToken');
    expect(registeredTokens(), <String>['fcm-token-1']);
  });

  test('a token that arrives after the session ended is not registered',
      () async {
    final Completer<String?> slowToken = Completer<String?>();
    messaging.pendingTokenRequest = slowToken;

    final Future<void> starting = controller.start();
    await pumpEventQueue();
    expect(messaging.calls, <String>['getToken']);

    final Future<void> stopping = controller.stop();
    slowToken.complete('late-token');
    await starting;
    await stopping;

    expect(recorded, isEmpty);
    expect(messaging.calls, <String>['getToken', 'deleteToken']);
  });

  test('switching accounts deletes the old token before asking for a new one',
      () async {
    await controller.start();
    messaging.calls.clear();

    final Future<void> stopping = controller.stop();
    final Future<void> starting = controller.start();
    await stopping;
    await starting;

    expect(messaging.calls, <String>['deleteToken', 'getToken']);
  });

  test('a failed registration never throws', () async {
    statusCode = 500;

    await expectLater(controller.start(), completes);
  });
}
