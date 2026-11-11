import 'package:flutter/widgets.dart';

import 'app_visibility.dart';

/// Exposes the session's [AppVisibility] to pushed routes.
///
/// Installed above `MaterialApp` in `main.dart`, like [RealtimeScope], so a
/// per-screen controller created by a pushed screen (the open chat thread)
/// can pause its polling when the app is backgrounded without threading the
/// lifecycle observer through constructors.
///
/// [maybeOf] is nullable on purpose: polling is additive, and a screen must
/// keep working when the scope is absent (widget tests, or a host that does
/// not provide it). In that case the controller simply does not poll.
class AppVisibilityScope extends InheritedWidget {
  const AppVisibilityScope({
    required this.visibility,
    required super.child,
    super.key,
  });

  final AppVisibility visibility;

  /// The visibility signal, or `null` when no scope is installed.
  ///
  /// Safe from `initState` ([getInheritedWidgetOfExactType] registers no
  /// dependency).
  static AppVisibility? maybeOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<AppVisibilityScope>()?.visibility;
  }

  @override
  bool updateShouldNotify(AppVisibilityScope oldWidget) =>
      visibility != oldWidget.visibility;
}
