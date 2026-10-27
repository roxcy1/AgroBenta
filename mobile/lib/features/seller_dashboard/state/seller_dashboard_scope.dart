import 'package:flutter/widgets.dart';

import '../../../repositories/seller_dashboard_repository.dart';

/// Makes the seller dashboard repository available to Seller Home.
///
/// Installed above `MaterialApp` in `main.dart` like every other feature scope,
/// so Seller Home resolves it the same way whether it is reached as a shell tab
/// or from a test harness.
class SellerDashboardScope extends InheritedWidget {
  const SellerDashboardScope({
    required this.repository,
    required super.child,
    super.key,
  });

  final SellerDashboardRepository repository;

  static SellerDashboardRepository readOf(BuildContext context) {
    final SellerDashboardScope? scope = context
        .getInheritedWidgetOfExactType<SellerDashboardScope>();
    assert(scope != null, 'No SellerDashboardScope found in context.');
    return scope!.repository;
  }

  @override
  bool updateShouldNotify(SellerDashboardScope oldWidget) =>
      repository != oldWidget.repository;
}
