import 'dart:convert';

import 'package:agrobenta_mobile/features/notification_settings/view/notification_settings_screen.dart';
import 'package:agrobenta_mobile/features/notifications/state/notifications_controller.dart';
import 'package:agrobenta_mobile/features/notifications/state/notifications_scope.dart';
import 'package:agrobenta_mobile/models/notification_preferences.dart';
import 'package:agrobenta_mobile/repositories/notification_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/notification_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  setUp(() {
    tokenStore = FakeTokenStore('token');
    recorded = <RecordedRequest>[];
  });

  NotificationRepository repository(
    Future<http.Response> Function(RecordedRequest request) handler,
  ) => buildNotificationRepository(tokenStore, handler, recorded: recorded);

  group('NotificationPreferences', () {
    test('reads the four switches from the resource', () {
      final NotificationPreferences preferences =
          NotificationPreferences.fromJson(
            notificationPreferencesJson(messages: false, verification: false),
          );

      expect(preferences.isEnabled(NotificationCategory.transactions), isTrue);
      expect(preferences.isEnabled(NotificationCategory.messages), isFalse);
      expect(preferences.isEnabled(NotificationCategory.listings), isTrue);
      expect(preferences.isEnabled(NotificationCategory.verification), isFalse);
    });

    test('withCategory changes only that switch', () {
      final NotificationPreferences changed = NotificationPreferences.fromJson(
        notificationPreferencesJson(),
      ).withCategory(NotificationCategory.listings, enabled: false);

      expect(
        NotificationCategory.values.where(changed.isEnabled),
        <NotificationCategory>[
          NotificationCategory.transactions,
          NotificationCategory.messages,
          NotificationCategory.verification,
        ],
      );
    });

    test('the keys match the API', () {
      expect(
        NotificationCategory.values.map((NotificationCategory c) => c.value),
        <String>['transactions', 'messages', 'listings', 'verification'],
      );
    });
  });

  group('NotificationService', () {
    test('GET reads the preferences', () async {
      final NotificationPreferences preferences = await repository(
        (_) async => notificationPreferencesResponse(),
      ).preferences();

      expect(preferences.isEnabled(NotificationCategory.messages), isTrue);
      expect(recorded.single.method, 'GET');
      expect(recorded.single.apiPath, '/notification-preferences');
    });

    test('PUT sends only the changed switch', () async {
      await repository(
        (_) async => notificationPreferencesResponse(
          preferences: notificationPreferencesJson(listings: false),
        ),
      ).updatePreference(NotificationCategory.listings, enabled: false);

      expect(recorded.single.method, 'PUT');
      expect(recorded.single.apiPath, '/notification-preferences');
      expect(recorded.single.body, <String, dynamic>{'listings': false});
    });
  });

  group('NotificationSettingsScreen', () {
    Future<void> pumpScreen(
      WidgetTester tester,
      Future<http.Response> Function(RecordedRequest request) handler,
    ) async {
      final NotificationRepository repo = repository(handler);
      final NotificationsController controller = NotificationsController(repo);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        NotificationsScope(
          repository: repo,
          controller: controller,
          child: const MaterialApp(home: NotificationSettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    bool switchValue(WidgetTester tester, String label) => tester
        .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, label))
        .value;

    testWidgets('shows one switch per type with the saved values', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        (_) async => notificationPreferencesResponse(
          preferences: notificationPreferencesJson(listings: false),
        ),
      );

      expect(find.byType(SwitchListTile), findsNWidgets(4));
      expect(switchValue(tester, 'Transactions'), isTrue);
      expect(switchValue(tester, 'Messages'), isTrue);
      expect(switchValue(tester, 'Listings'), isFalse);
      expect(switchValue(tester, 'Seller Verification'), isTrue);
      expect(
        find.textContaining('still show in Notifications in the app'),
        findsOneWidget,
      );
    });

    testWidgets('turning a switch off saves it', (WidgetTester tester) async {
      await pumpScreen(
        tester,
        (RecordedRequest request) async => request.method == 'PUT'
            ? notificationPreferencesResponse(
                preferences: notificationPreferencesJson(messages: false),
              )
            : notificationPreferencesResponse(),
      );

      await tester.tap(find.widgetWithText(SwitchListTile, 'Messages'));
      await tester.pumpAndSettle();

      expect(switchValue(tester, 'Messages'), isFalse);
      final RecordedRequest put = recorded.lastWhere(
        (RecordedRequest r) => r.method == 'PUT',
      );
      expect(put.body, <String, dynamic>{'messages': false});
    });

    testWidgets('a failed save puts the switch back and says so', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        (RecordedRequest request) async => request.method == 'PUT'
            ? http.Response(
                jsonEncode(<String, dynamic>{'message': 'Server Error'}),
                500,
                headers: <String, String>{'content-type': 'application/json'},
              )
            : notificationPreferencesResponse(),
      );

      await tester.tap(find.widgetWithText(SwitchListTile, 'Transactions'));
      await tester.pumpAndSettle();

      expect(switchValue(tester, 'Transactions'), isTrue);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('a failed load offers a retry', (WidgetTester tester) async {
      int calls = 0;
      await pumpScreen(
        tester,
        (_) async => ++calls == 1
            ? http.Response(
                jsonEncode(<String, dynamic>{'message': 'Server Error'}),
                500,
                headers: <String, String>{'content-type': 'application/json'},
              )
            : notificationPreferencesResponse(),
      );

      expect(find.byType(SwitchListTile), findsNothing);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.byType(SwitchListTile), findsNWidgets(4));
    });
  });
}
