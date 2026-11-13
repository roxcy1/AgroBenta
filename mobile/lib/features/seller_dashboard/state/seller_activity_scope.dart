import 'package:flutter/widgets.dart';

import '../../../repositories/seller_activity_repository.dart';

/// Makes the seller activity repository available to Seller Home.
///
/// Installed above `MaterialApp` like the other repositories. The dashboard
/// creates its own controller per mount, so a failure or refresh in the
/// activity feed cannot disturb the summary or inquiry sections.
class SellerActivityScope extends InheritedWidget {
  const SellerActivityScope({
    required this.repository,
    required super.child,
    super.key,
  });

  final SellerActivityRepository repository;

  static SellerActivityRepository readOf(BuildContext context) {
    final SellerActivityScope? scope =
        context.getInheritedWidgetOfExactType<SellerActivityScope>();
    assert(scope != null, 'No SellerActivityScope found in context.');
    return scope!.repository;
  }

  @override
  bool updateShouldNotify(SellerActivityScope oldWidget) =>
      repository != oldWidget.repository;
}
