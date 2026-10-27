import 'package:flutter/widgets.dart';

import '../../../repositories/profile_repository.dart';
import 'profile_controller.dart';

/// The profile controller, for the screens that need it.
///
/// A plain [InheritedWidget], like the other scopes in this app: the screens in
/// this feature listen with `ListenableBuilder`, so a widget that only has to
/// *reach* the controller does not need to rebuild when it notifies.
///
/// Installed above `MaterialApp` in `main.dart`, so the profile screen pushed
/// from the buyer shell can reach it — a scope inside `home` would be invisible
/// to a pushed route, the same problem every other scope in this app solves the
/// same way.
class ProfileScope extends InheritedWidget {
  const ProfileScope({
    required this.repository,
    required this.controller,
    required super.child,
    super.key,
  });

  final ProfileRepository repository;
  final ProfileController controller;

  /// The controller, registering [context] as a dependency.
  ///
  /// Correct from `build` and below. Calling it during `initState` throws.
  static ProfileController of(BuildContext context) {
    final ProfileScope? scope = context
        .dependOnInheritedWidgetOfExactType<ProfileScope>();
    assert(scope != null, 'No ProfileScope found in context.');
    return scope!.controller;
  }

  /// The controller, **without** registering a dependency.
  ///
  /// For `initState`, where a dependency cannot be registered and where
  /// rebuilding the whole screen on every keystroke would be wrong anyway.
  static ProfileController readOf(BuildContext context) {
    final ProfileScope? scope = context
        .getInheritedWidgetOfExactType<ProfileScope>();
    assert(scope != null, 'No ProfileScope found in context.');
    return scope!.controller;
  }

  @override
  bool updateShouldNotify(ProfileScope oldWidget) =>
      repository != oldWidget.repository || controller != oldWidget.controller;
}