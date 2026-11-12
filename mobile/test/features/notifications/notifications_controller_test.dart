import 'dart:async';

import 'package:agrobenta_mobile/features/notifications/state/notifications_controller.dart';
import 'package:agrobenta_mobile/features/notifications/state/notifications_state.dart';
import 'package:agrobenta_mobile/repositories/notification_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/notification_fakes.dart';

void main() {
  group('NotificationsController.load', () {
    test('the first load fetches page 1 and becomes ready', () async {
      final List<RecordedRequest> recorded = <RecordedRequest>[];
      final NotificationRepository repository = buildNotificationRepository(
        FakeTokenStore('token'),
        (RecordedRequest request) async => notificationsPageResponse(
          notifications: <Map<String, dynamic>>[notificationJson()],
          unreadCount: 1,
        ),
        recorded: recorded,
      );
      final NotificationsController controller = NotificationsController(
        repository,
      );
      addTearDown(controller.dispose);

      // Regression: a guard on `isInitialLoad` (true for `initial` as well as
      // `loading`) made this first call return at once, so the screen showed
      // its spinner forever and no list request was ever sent.
      await controller.load();

      expect(
        recorded.where((r) => r.apiPath == '/notifications'),
        hasLength(1),
      );
      expect(controller.state.status, NotificationsStatus.ready);
      expect(controller.state.notifications, hasLength(1));
      expect(controller.state.unreadCount, 1);
    });

    test(
      'a second call while one is in flight sends no second request',
      () async {
        final List<RecordedRequest> recorded = <RecordedRequest>[];
        final Completer<http.Response> gate = Completer<http.Response>();
        final NotificationRepository repository = buildNotificationRepository(
          FakeTokenStore('token'),
          (RecordedRequest request) => gate.future,
          recorded: recorded,
        );
        final NotificationsController controller = NotificationsController(
          repository,
        );
        addTearDown(controller.dispose);

        final Future<void> first = controller.load();
        await Future<void>.delayed(Duration.zero);
        await controller.load();

        expect(controller.state.status, NotificationsStatus.loading);
        expect(
          recorded.where((r) => r.apiPath == '/notifications'),
          hasLength(1),
        );

        gate.complete(notificationsPageResponse());
        await first;
        expect(controller.state.status, NotificationsStatus.ready);
      },
    );
  });
}
