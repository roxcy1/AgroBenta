import 'package:flutter/widgets.dart';

import '../../../repositories/app_release_repository.dart';

/// Makes the app release repository available to the App Update tile.
///
/// Installed above `MaterialApp` like the other repositories. The tile creates
/// its own controller and disposes it with the Profile screen.
class AppUpdateScope extends InheritedWidget {
  const AppUpdateScope({
    required this.repository,
    required super.child,
    super.key,
  });

  final AppReleaseRepository repository;

  static AppReleaseRepository readOf(BuildContext context) {
    final AppUpdateScope? scope = context
        .getInheritedWidgetOfExactType<AppUpdateScope>();
    assert(scope != null, 'No AppUpdateScope found in context.');
    return scope!.repository;
  }

  @override
  bool updateShouldNotify(AppUpdateScope oldWidget) =>
      repository != oldWidget.repository;
}
