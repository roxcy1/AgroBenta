import 'package:flutter/widgets.dart';

import 'realtime_controller.dart';

/// Exposes the session's [RealtimeController] to pushed routes.
///
/// Installed above `MaterialApp` in `main.dart`, like every other feature
/// scope, so a pushed screen (chat, offer panel, transaction detail, …) can
/// subscribe without threading the controller through every constructor.
///
/// [maybeOf] is nullable on purpose: real-time is additive, and a screen must
/// keep working when the scope is absent (widget tests, or a host that does not
/// provide real-time). Use [of] only where the scope is guaranteed.
class RealtimeScope extends InheritedWidget {
  const RealtimeScope({
    required this.controller,
    required super.child,
    super.key,
  });

  final RealtimeController controller;

  /// The controller, registering [context] as a dependency.
  static RealtimeController of(BuildContext context) {
    final RealtimeScope? scope =
        context.dependOnInheritedWidgetOfExactType<RealtimeScope>();
    assert(scope != null, 'No RealtimeScope found in context.');
    return scope!.controller;
  }

  /// The controller, or `null` when no scope is installed.
  ///
  /// Safe from `initState` ([getInheritedWidgetOfExactType] registers no
  /// dependency).
  static RealtimeController? maybeOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<RealtimeScope>()?.controller;
  }

  @override
  bool updateShouldNotify(RealtimeScope oldWidget) =>
      controller != oldWidget.controller;
}
