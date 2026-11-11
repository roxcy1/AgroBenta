import 'dart:convert';

import 'package:agrobenta_mobile/core/storage/account_mode_preference_store.dart';
import 'package:agrobenta_mobile/features/auth/view/sign_in_screen.dart';
import 'package:agrobenta_mobile/features/buyer_shell/view/buyer_shell.dart';
import 'package:agrobenta_mobile/features/notifications/view/notifications_screen.dart';
import 'package:agrobenta_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/auth_fakes.dart';
import '../../support/marketplace_fakes.dart';
import '../../support/messaging_fakes.dart';
import '../../support/notification_fakes.dart';
import '../../support/push_fakes.dart';
import '../../support/transaction_fakes.dart';

class _MemoryAccountModeStore implements AccountModePreferenceStore {
  final Map<int, String> values = <int, String>{};

  @override
  Future<String?> read(int userId) async => values[userId];

  @override
  Future<void> write(int userId, String mode) async {
    values[userId] = mode;
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (int frame = 0; frame < 12; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// App-level push wiring: the session registers the phone, and a tapped push
/// opens the Notifications screen.
void main() {
  late List<RecordedRequest> recorded;
  late MockClient httpClient;

  http.Response jsonResponse(Object body, {int status = 200}) => http.Response(
    jsonEncode(body),
    status,
    headers: const <String, String>{'content-type': 'application/json'},
  );

  setUp(() {
    recorded = <RecordedRequest>[];
    httpClient = MockClient((http.Request request) async {
      final RecordedRequest entry = RecordedRequest(request);
      recorded.add(entry);

      switch (entry.apiPath) {
        case '/auth/me':
          return jsonResponse(successEnvelope(data: userJson(id: 7)));
        case '/auth/logout':
          return jsonResponse(successEnvelope(message: 'Logged out.'));
        case '/devices':
          return deviceRegisteredResponse();
        case '/conversations':
          return conversationsResponse(
            conversations: const <Map<String, dynamic>>[],
          );
        case '/listings':
          return marketplaceListResponse(listings: const [], total: 0);
        case '/marketplace/popular-livestock':
          return popularLivestockResponse();
        case '/transactions':
          return transactionListResponse(transactions: const [], total: 0);
        case '/notifications':
          return notificationsPageResponse();
        case '/notifications/unread-count':
          return unreadCountResponse();
        case '/seller-verification/me':
          return http.Response(jsonEncode('No seller verification.'), 404);
        default:
          return jsonResponse(<String, dynamic>{
            'message': 'Not found.',
          }, status: 404);
      }
    });
  });

  tearDown(() => httpClient.close());

  List<RecordedRequest> deviceRequests() => recorded
      .where((RecordedRequest r) => r.apiPath == '/devices')
      .toList();

  testWidgets('a restored session registers the phone with its bearer token', (
    WidgetTester tester,
  ) async {
    final FakePushMessaging push = FakePushMessaging();
    addTearDown(push.close);

    await tester.pumpWidget(
      AgroBentaApp(
        tokenStore: FakeTokenStore('user-a-token'),
        accountModePreferenceStore: _MemoryAccountModeStore(),
        httpClient: httpClient,
        pushMessaging: push,
      ),
    );
    await _settle(tester);

    expect(find.byType(BuyerShell), findsOneWidget);
    expect(deviceRequests(), hasLength(1));
    expect(deviceRequests().single.authorization, 'Bearer user-a-token');
    expect(deviceRequests().single.body, <String, dynamic>{
      'token': 'fcm-token-1',
    });
  });

  testWidgets('a signed-out app does not register the phone', (
    WidgetTester tester,
  ) async {
    final FakePushMessaging push = FakePushMessaging();
    addTearDown(push.close);

    await tester.pumpWidget(
      AgroBentaApp(
        tokenStore: FakeTokenStore(),
        accountModePreferenceStore: _MemoryAccountModeStore(),
        httpClient: httpClient,
        pushMessaging: push,
      ),
    );
    await _settle(tester);

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(push.calls, isEmpty);
    expect(deviceRequests(), isEmpty);
  });

  testWidgets('the Home bell opens the Notifications screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      AgroBentaApp(
        tokenStore: FakeTokenStore('user-a-token'),
        accountModePreferenceStore: _MemoryAccountModeStore(),
        httpClient: httpClient,
      ),
    );
    await _settle(tester);

    await tester.tap(find.byTooltip('Notifications'));
    await _settle(tester);

    expect(find.byType(NotificationsScreen), findsOneWidget);
  });

  testWidgets('tapping a push opens the Notifications screen', (
    WidgetTester tester,
  ) async {
    final FakePushMessaging push = FakePushMessaging();
    addTearDown(push.close);

    await tester.pumpWidget(
      AgroBentaApp(
        tokenStore: FakeTokenStore('user-a-token'),
        accountModePreferenceStore: _MemoryAccountModeStore(),
        httpClient: httpClient,
        pushMessaging: push,
      ),
    );
    await _settle(tester);
    expect(find.byType(NotificationsScreen), findsNothing);

    push.opened.add(<String, String>{'type': 'listing', 'action': 'listing'});
    await _settle(tester);

    expect(find.byType(NotificationsScreen), findsOneWidget);
  });

  testWidgets('a push tapped before sign-in opens once the session is back', (
    WidgetTester tester,
  ) async {
    final FakePushMessaging push = FakePushMessaging();
    addTearDown(push.close);

    await tester.pumpWidget(
      AgroBentaApp(
        tokenStore: FakeTokenStore('user-a-token'),
        accountModePreferenceStore: _MemoryAccountModeStore(),
        httpClient: httpClient,
        pushMessaging: push,
      ),
    );
    // The cold-start push arrives before /auth/me has restored the session.
    push.opened.add(<String, String>{'type': 'transaction'});
    await _settle(tester);

    expect(find.byType(NotificationsScreen), findsOneWidget);
  });
}
