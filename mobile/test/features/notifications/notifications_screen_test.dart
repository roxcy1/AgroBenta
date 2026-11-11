import 'dart:convert';

import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/notifications/state/notifications_controller.dart';
import 'package:agrobenta_mobile/features/notifications/state/notifications_scope.dart';
import 'package:agrobenta_mobile/features/notifications/view/notifications_screen.dart';
import 'package:agrobenta_mobile/models/app_notification.dart';
import 'package:agrobenta_mobile/repositories/notification_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/notification_fakes.dart';

/// The AppBar's "Mark all read" action.
///
/// Before the dialog opens it is the only widget with this label; inside the
/// dialog there is a second one, so tests scope their finder to the
/// `AlertDialog` or to the AppBar as needed.
void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  setUp(() {
    tokenStore = FakeTokenStore('1|mobile-token');
    recorded = <RecordedRequest>[];
  });

  Future<void> settle(WidgetTester tester, {int frames = 8}) async {
    for (int frame = 0; frame < frames; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// A two-notification inbox, both unread, with a working read-all endpoint.
  Future<http.Response> unreadInbox(RecordedRequest request) async {
    switch (request.apiPath) {
      case '/notifications/unread-count':
        return unreadCountResponse(count: 2);
      case '/notifications/read-all':
        return http.Response(
          jsonEncode(successEnvelope(data: <String, dynamic>{'count': 2})),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      default:
        return notificationsPageResponse(
          notifications: <Map<String, dynamic>>[
            notificationJson(id: 'first-notification', title: 'New inquiry'),
            notificationJson(
              id: 'second-notification',
              title: 'Listing approved',
              type: 'listing',
            ),
          ],
          unreadCount: 2,
        );
    }
  }

  Future<NotificationsController> pumpScreen(
    WidgetTester tester, {
    required Future<http.Response> Function(RecordedRequest request) handler,
  }) async {
    final NotificationRepository repository = buildNotificationRepository(
      tokenStore,
      handler,
      recorded: recorded,
    );
    final NotificationsController controller = NotificationsController(
      repository,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      NotificationsScope(
        repository: repository,
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const NotificationsScreen(),
        ),
      ),
    );
    await settle(tester);
    return controller;
  }

  Finder appBarAction() => find.widgetWithText(TextButton, 'Mark all read');

  Finder dialogAction() => find.descendant(
    of: find.byType(AlertDialog),
    matching: find.widgetWithText(TextButton, 'Mark all read'),
  );

  int readAllCalls() => recorded
      .where((RecordedRequest r) => r.apiPath == '/notifications/read-all')
      .length;

  testWidgets('asks for confirmation before marking everything read', (
    WidgetTester tester,
  ) async {
    final NotificationsController controller = await pumpScreen(
      tester,
      handler: unreadInbox,
    );

    await tester.tap(appBarAction());
    await settle(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Mark all as read?'), findsOneWidget);
    expect(readAllCalls(), 0, reason: 'opening the dialog must not write');

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await settle(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(readAllCalls(), 0, reason: 'cancelling must not mark anything');
    expect(controller.state.unreadCount, 2);
    expect(
      controller.state.notifications.every((AppNotification n) => !n.read),
      isTrue,
    );
  });

  testWidgets('confirming marks everything read and clears the badge', (
    WidgetTester tester,
  ) async {
    final NotificationsController controller = await pumpScreen(
      tester,
      handler: unreadInbox,
    );

    await tester.tap(appBarAction());
    await settle(tester);
    await tester.tap(dialogAction());
    await settle(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(readAllCalls(), 1);
    expect(controller.state.unreadCount, 0);
    expect(
      controller.state.notifications.every((AppNotification n) => n.read),
      isTrue,
    );
    expect(
      tester.widget<TextButton>(appBarAction()).onPressed,
      isNull,
      reason: 'nothing is unread, so the action is disabled',
    );
  });

  testWidgets('the action is disabled when nothing is unread', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      handler: (RecordedRequest request) async =>
          request.apiPath == '/notifications/unread-count'
          ? unreadCountResponse(count: 0)
          : notificationsPageResponse(
              notifications: <Map<String, dynamic>>[
                notificationJson(id: 'already-read', read: true),
              ],
            ),
    );

    expect(tester.widget<TextButton>(appBarAction()).onPressed, isNull);
  });
}
