import 'package:flutter/widgets.dart';

import '../../../repositories/seller_listing_repository.dart';
import 'seller_listing_controller.dart';

/// The seller listing controller, for the screens that need it.
///
/// A plain [InheritedWidget] rather than an `InheritedNotifier`, for the same
/// reason `MarketplaceScope` is one: the screens in this feature listen with
/// `ListenableBuilder`, so a widget that only had to *reach* the controller does
/// not need to rebuild when it notifies.
///
/// `main.dart` installs this **above** `MaterialApp`. The detail, form and
/// deletion-confirmation screens are all pushed on top of the buyer shell, and
/// anything provided from inside `home` would be invisible to them for the same
/// reason the existing scopes must sit above the app.
class SellerListingScope extends InheritedWidget {
  const SellerListingScope({
    required this.repository,
    required this.controller,
    required super.child,
    super.key,
  });

  final SellerListingRepository repository;
  final SellerListingController controller;

  /// The controller, registering [context] as a dependency.
  ///
  /// Correct from `build` and below. Calling it during `initState` throws,
  /// because `dependOnInheritedWidgetOfExactType` may not be used before
  /// `initState` completes.
  static SellerListingController of(BuildContext context) {
    final SellerListingScope? scope = context
        .dependOnInheritedWidgetOfExactType<SellerListingScope>();
    assert(scope != null, 'No SellerListingScope found in context.');
    return scope!.controller;
  }

  /// The controller, **without** registering a dependency.
  ///
  /// For `initState`, where a dependency cannot be registered and where
  /// rebuilding the whole screen on every keystroke would be wrong anyway.
  static SellerListingController readOf(BuildContext context) {
    final SellerListingScope? scope = context
        .getInheritedWidgetOfExactType<SellerListingScope>();
    assert(scope != null, 'No SellerListingScope found in context.');
    return scope!.controller;
  }

  @override
  bool updateShouldNotify(SellerListingScope oldWidget) =>
      repository != oldWidget.repository || controller != oldWidget.controller;
}
