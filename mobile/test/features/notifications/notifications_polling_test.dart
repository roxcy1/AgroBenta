import 'dart:async';

import 'package:agrobenta_mobile/features/notifications/state/notifications_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/auth_fakes.dart';
import '../../support/notification_fakes.dart';

/// The badge must correct itself without a pull-to-refresh, and must stop
/// spending requests when the app is not in front of the user.
///
/// Driven with `testWidgets` so the poll timer runs on the test binding's
/// fake clock: `tester.pump(interval)` fires exactly one tick, and no real
/// wall-clock time is spent.
void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;
  late StreamController<bool> visibility;

  setUp(() {
    tokenStore = FakeTokenStore('1|mobile-token');
    recorded = <RecordedRequest>[];
    visibility = StreamController<bool>.broadcast();
  });

  tearDown(() async {
    await visibility.close();
  });

  int unreadRequests() => recorded
      .where((RecordedRequest r) => r.apiPath == '/notifications/unread-count')
      .length;

  testWidgets('the unread badge refreshes itself while in the foreground', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());

    int count = 1;
    final NotificationsController controller = NotificationsController(
      buildNotificationRepository(
        tokenStore,
        (RecordedRequest request) async => unreadCountResponse(count: count),
        recorded: recorded,
      ),
      appVisibility: visibility.stream,
      pollInterval: const Duration(seconds: 30),
    );

    await controller.refreshUnreadCount();
    expect(controller.state.unreadCount, 1);
    recorded.clear();

    // A new notification arrives on the server; nothing tells the client.
    count = 4;
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();

    expect(controller.state.unreadCount, 4);
    expect(unreadRequests(), 1);

    // The binding asserts no timer outlives the test body, so the periodic
    // timer is cancelled here rather than in a teardown callback.
    controller.dispose();
  });

  testWidgets('polling stops in the background and catches up on return', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());

    int count = 2;
    final NotificationsController controller = NotificationsController(
      buildNotificationRepository(
        tokenStore,
        (RecordedRequest request) async => unreadCountResponse(count: count),
        recorded: recorded,
      ),
      appVisibility: visibility.stream,
      pollInterval: const Duration(seconds: 30),
    );

    await controller.refreshUnreadCount();
    recorded.clear();

    visibility.add(false);
    await tester.pump();

    // Two intervals pass while the app is backgrounded: no requests at all.
    await tester.pump(const Duration(minutes: 1));
    await tester.pump();
    expect(recorded, isEmpty);
    expect(controller.state.unreadCount, 2);

    // Returning to the foreground reconciles immediately, not after an
    // interval.
    count = 6;
    visibility.add(true);
    await tester.pump();
    await tester.pump();

    expect(controller.state.unreadCount, 6);
    expect(unreadRequests(), 1);

    controller.dispose();
  });

  testWidgets('without a visibility signal nothing polls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());

    final NotificationsController controller = NotificationsController(
      buildNotificationRepository(
        tokenStore,
        (RecordedRequest request) async => unreadCountResponse(count: 3),
        recorded: recorded,
      ),
    );

    await tester.pump(const Duration(minutes: 2));
    await tester.pump();

    expect(recorded, isEmpty);

    controller.dispose();
  });
}
