import 'dart:async';
import 'dart:convert';

import 'package:agrobenta_mobile/core/storage/account_mode_preference_store.dart';
import 'package:agrobenta_mobile/features/auth/view/sign_in_screen.dart';
import 'package:agrobenta_mobile/features/buyer_shell/view/buyer_shell.dart';
import 'package:agrobenta_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/auth_fakes.dart';
import '../../support/marketplace_fakes.dart';
import '../../support/messaging_fakes.dart';
import '../../support/notification_fakes.dart';
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

void main() {
  testWidgets(
    'User B stays isolated after tab switches and User A responses cannot repopulate tabs',
    (WidgetTester tester) async {
      final FakeTokenStore tokenStore = FakeTokenStore('user-a-token');
      final _MemoryAccountModeStore modeStore = _MemoryAccountModeStore();
      final List<RecordedRequest> recorded = <RecordedRequest>[];
      final Completer<http.Response> delayedUserAInbox =
          Completer<http.Response>();
      final Map<String, dynamic> userA = userJson(
        id: 7,
        name: 'Ana Reyes',
        email: 'ana@example.test',
      );
      final Map<String, dynamic> userB = userJson(
        id: 8,
        name: 'Ben Cruz',
        email: 'ben@example.test',
      );

      http.Response jsonResponse(Object body, {int status = 200}) =>
          http.Response(
            jsonEncode(body),
            status,
            headers: const <String, String>{'content-type': 'application/json'},
          );

      final MockClient httpClient = MockClient((http.Request request) async {
        final RecordedRequest entry = RecordedRequest(request);
        recorded.add(entry);
        final bool isUserA = entry.authorization == 'Bearer user-a-token';

        switch (entry.apiPath) {
          case '/auth/me':
            return jsonResponse(successEnvelope(data: isUserA ? userA : userB));
          case '/auth/login':
            final Map<String, dynamic> loginBody = entry.body;
            final bool loginAsA = loginBody['email'] == 'ana@example.test';
            final Map<String, dynamic> user = loginAsA ? userA : userB;
            final String token = loginAsA ? 'user-a-token' : 'user-b-token';
            return jsonResponse(
              successEnvelope(
                data: authSessionJson(token: token, user: user),
              ),
            );
          case '/auth/logout':
            return jsonResponse(successEnvelope(message: 'Logged out.'));
          case '/profile':
            return jsonResponse(successEnvelope(data: isUserA ? userA : userB));
          case '/conversations':
            if (isUserA && !delayedUserAInbox.isCompleted) {
              return delayedUserAInbox.future;
            }
            return conversationsResponse(
              conversations: <Map<String, dynamic>>[
                conversationJson(
                  counterpart: chatUserJson(
                    id: isUserA ? 17 : 18,
                    name: isUserA ? 'User A contact' : 'User B contact',
                  ),
                ),
              ],
            );
          case '/livestock-types':
            return jsonResponse(<String, Object>{
              'data': <Map<String, String>>[
                <String, String>{'value': 'cattle', 'label': 'Cattle'},
                <String, String>{'value': 'carabao', 'label': 'Carabao'},
                <String, String>{'value': 'goat', 'label': 'Goat'},
                <String, String>{'value': 'swine', 'label': 'Swine'},
              ],
            });
          case '/listings':
            return marketplaceListResponse(listings: const [], total: 0);
          case '/marketplace/popular-livestock':
            return popularLivestockResponse();
          case '/transactions':
            return transactionListResponse(transactions: const [], total: 0);
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

      addTearDown(httpClient.close);
      await tester.pumpWidget(
        AgroBentaApp(
          tokenStore: tokenStore,
          accountModePreferenceStore: modeStore,
          httpClient: httpClient,
        ),
      );
      await _settle(tester);

      expect(find.byType(BuyerShell), findsOneWidget);
      expect(
        recorded.any(
          (RecordedRequest request) =>
              request.apiPath == '/conversations' &&
              request.authorization == 'Bearer user-a-token',
        ),
        isTrue,
      );

      await _openProfile(tester);
      expect(find.text('Ana Reyes'), findsOneWidget);
      await _logout(tester);
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(tokenStore.token, isNull);

      await _login(tester, 'ben@example.test');
      expect(tokenStore.token, 'user-b-token');
      expect(find.byType(BuyerShell), findsOneWidget);
      await _openProfile(tester);
      expect(find.text('Ben Cruz'), findsOneWidget);
      expect(find.text('Ana Reyes'), findsNothing);

      // A's old request completes only after B has logged in and loaded their
      // inbox. Its controller was disposed at the session boundary.
      delayedUserAInbox.complete(
        conversationsResponse(
          conversations: <Map<String, dynamic>>[
            conversationJson(
              counterpart: chatUserJson(id: 17, name: 'User A contact'),
            ),
          ],
        ),
      );
      await _settle(tester);

      await _tapDestination(tester, 'Browse');
      await _tapDestination(tester, 'Messages');
      await _settle(tester);
      expect(find.text('User B contact'), findsOneWidget);
      expect(find.text('User A contact'), findsNothing);
      expect(
        recorded.any(
          (RecordedRequest request) =>
              request.apiPath == '/conversations' &&
              request.authorization == 'Bearer user-b-token',
        ),
        isTrue,
      );

      // Repeat the switch in the other direction to verify this is not a
      // one-off reset that only happens for the first replacement account.
      await _logout(tester);
      await _login(tester, 'ana@example.test');
      expect(tokenStore.token, 'user-a-token');
      await _openProfile(tester);
      expect(find.text('Ana Reyes'), findsOneWidget);
      expect(find.text('Ben Cruz'), findsNothing);
      await _tapDestination(tester, 'Messages');
      await _settle(tester);
      expect(find.text('User A contact'), findsOneWidget);
      expect(find.text('User B contact'), findsNothing);
    },
  );
}

Future<void> _openProfile(WidgetTester tester) async {
  final Finder destination = find.widgetWithText(
    NavigationDestination,
    'Profile',
  );
  await tester.ensureVisible(destination);
  await tester.tap(destination);
  await _settle(tester);
}

Future<void> _logout(WidgetTester tester) async {
  await _openProfile(tester);
  final Finder logout = find.widgetWithText(ListTile, 'Log Out');
  await tester.ensureVisible(logout);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(logout);
  await _settle(tester);
}

Future<void> _login(WidgetTester tester, String email) async {
  await tester.enterText(find.byType(TextFormField).at(0), email);
  await tester.enterText(find.byType(TextFormField).at(1), 'correct horse');
  final Finder button = find.widgetWithText(FilledButton, 'Log In');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await _settle(tester);
}

Future<void> _tapDestination(WidgetTester tester, String label) async {
  final Finder destination = find.widgetWithText(NavigationDestination, label);
  await tester.ensureVisible(destination);
  await tester.tap(destination);
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _settle(WidgetTester tester) async {
  for (int frame = 0; frame < 12; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
