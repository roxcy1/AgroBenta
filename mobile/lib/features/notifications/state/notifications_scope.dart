import 'package:flutter/widgets.dart';

import '../../../repositories/notification_repository.dart';
import 'notifications_controller.dart';

/// Makes the shared [NotificationRepository] and the session-scoped
/// [NotificationsController] available to the screens that need them.
///
/// Installed above `MaterialApp` in `main.dart`, like every other feature
/// scope. The controller is session-scoped so the bell icon on Home's AppBar
/// and the Notifications screen read the same state — a per-screen controller
/// would need its own badge count and could disagree with the list.
class NotificationsScope extends InheritedWidget {
  const NotificationsScope({
    required this.repository,
    required this.controller,
    required super.child,
    super.key,
  });

  final NotificationRepository repository;
  final NotificationsController controller;

  /// The controller, registering [context] as a dependency.
  static NotificationsController of(BuildContext context) {
    final NotificationsScope? scope =
        context.dependOnInheritedWidgetOfExactType<NotificationsScope>();
    assert(scope != null, 'No NotificationsScope found in context.');
    return scope!.controller;
  }

  /// The controller, **without** registering a dependency. For `initState`.
  static NotificationsController readOf(BuildContext context) {
    final NotificationsScope? scope =
        context.getInheritedWidgetOfExactType<NotificationsScope>();
    assert(scope != null, 'No NotificationsScope found in context.');
    return scope!.controller;
  }

  @override
  bool updateShouldNotify(NotificationsScope oldWidget) =>
      repository != oldWidget.repository || controller != oldWidget.controller;
}