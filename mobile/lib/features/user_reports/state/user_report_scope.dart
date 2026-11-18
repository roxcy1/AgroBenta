import 'package:flutter/widgets.dart';

import '../../../repositories/user_report_repository.dart';

/// Publishes the user-report transport to the three entry points.
///
/// Installed above `MaterialApp`, like every other scope in this app, because
/// the report form is a pushed route that may be opened from the marketplace,
/// messaging, or transaction details.
class UserReportScope extends InheritedWidget {
  const UserReportScope({
    required this.repository,
    required super.child,
    super.key,
  });

  final UserReportRepository repository;

  static UserReportRepository readOf(BuildContext context) {
    final UserReportScope? scope = context
        .getInheritedWidgetOfExactType<UserReportScope>();
    assert(scope != null, 'No UserReportScope found in context.');
    return scope!.repository;
  }

  @override
  bool updateShouldNotify(UserReportScope oldWidget) =>
      repository != oldWidget.repository;
}
