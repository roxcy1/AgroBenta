import 'package:flutter/widgets.dart';

import '../../../models/livestock_type.dart';
import '../../../repositories/livestock_type_repository.dart';
import 'livestock_types_controller.dart';

/// Makes the shared livestock-type catalog available to every screen.
///
/// Installed above `MaterialApp` in `main.dart`, like the other feature scopes.
/// Display code should prefer [labelOf]: it is safe in tests that mount a screen
/// without the scope, where it falls back to title-casing the raw value.
class LivestockTypesScope extends InheritedWidget {
  const LivestockTypesScope({
    required this.repository,
    required this.controller,
    required super.child,
    super.key,
  });

  final LivestockTypeRepository repository;
  final LivestockTypesController controller;

  /// The controller, registering [context] as a dependency.
  static LivestockTypesController of(BuildContext context) {
    final LivestockTypesScope? scope =
        context.dependOnInheritedWidgetOfExactType<LivestockTypesScope>();
    assert(scope != null, 'No LivestockTypesScope found in context.');
    return scope!.controller;
  }

  /// The controller, **without** registering a dependency. For `initState`.
  static LivestockTypesController readOf(BuildContext context) {
    final LivestockTypesScope? scope =
        context.getInheritedWidgetOfExactType<LivestockTypesScope>();
    assert(scope != null, 'No LivestockTypesScope found in context.');
    return scope!.controller;
  }

  /// The display label for [raw], or a safe fallback when no scope is present.
  static String labelOf(BuildContext context, String raw) {
    final LivestockTypesScope? scope =
        context.dependOnInheritedWidgetOfExactType<LivestockTypesScope>();
    if (scope == null) {
      return LivestockType.titleCase(raw);
    }
    return scope.controller.state.labelFor(raw);
  }

  @override
  bool updateShouldNotify(LivestockTypesScope oldWidget) =>
      repository != oldWidget.repository || controller != oldWidget.controller;
}
