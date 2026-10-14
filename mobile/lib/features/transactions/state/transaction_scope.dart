import 'package:flutter/widgets.dart';

import '../../../repositories/transaction_repository.dart';

/// Makes the shared [TransactionRepository] available to pushed routes.
///
/// Installed above `MaterialApp` like every other feature scope: a route
/// pushed onto the navigator is a sibling of the home route, not a
/// descendant, so a scope inside `home` would be invisible to the
/// transaction detail screen.
class TransactionScope extends InheritedWidget {
  const TransactionScope({required this.repository, required super.child, super.key});

  final TransactionRepository repository;

  static TransactionRepository readOf(BuildContext context) {
    final TransactionScope? scope =
        context.getInheritedWidgetOfExactType<TransactionScope>();
    assert(scope != null, 'No TransactionScope found above this widget.');
    return scope!.repository;
  }

  @override
  bool updateShouldNotify(TransactionScope oldWidget) =>
      repository != oldWidget.repository;
}
