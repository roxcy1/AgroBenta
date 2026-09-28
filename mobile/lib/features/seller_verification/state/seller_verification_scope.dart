import 'package:flutter/widgets.dart';

import '../../../repositories/seller_verification_repository.dart';
import '../state/seller_verification_controller.dart';

/// The seller verification controller, for the screens that need it.
///
/// A plain [InheritedWidget] rather than an `InheritedNotifier`, for the same
/// reason `MarketplaceScope` is one: the two screens in this feature listen with
/// `ListenableBuilder`, so a widget that only had to *reach* the controller does
/// not need to rebuild when it notifies. That matters here because the
/// verification screen is pushed on top of the buyer shell — a scope inside
/// `home` would not be visible to it, which is why `main.dart` installs this
/// above `MaterialApp`.
class SellerVerificationScope extends InheritedWidget {
  const SellerVerificationScope({
    required this.repository,
    required this.controller,
    required super.child,
    super.key,
  });

  final SellerVerificationRepository repository;
  final SellerVerificationController controller;

  /// The controller, registering [context] as a dependency.
  ///
  /// Correct from `build` and below. Calling it during `initState` throws,
  /// because `dependOnInheritedWidgetOfExactType` may not be used before
  /// `initState` completes.
  static SellerVerificationController of(BuildContext context) {
    final SellerVerificationScope? scope = context
        .dependOnInheritedWidgetOfExactType<SellerVerificationScope>();
    assert(scope != null, 'No SellerVerificationScope found in context.');
    return scope!.controller;
  }

  /// The controller, **without** registering a dependency.
  ///
  /// For `initState`, where a dependency cannot be registered and where
  /// rebuilding the whole screen on every keystroke would be wrong anyway.
  static SellerVerificationController readOf(BuildContext context) {
    final SellerVerificationScope? scope = context
        .getInheritedWidgetOfExactType<SellerVerificationScope>();
    assert(scope != null, 'No SellerVerificationScope found in context.');
    return scope!.controller;
  }

  @override
  bool updateShouldNotify(SellerVerificationScope oldWidget) =>
      repository != oldWidget.repository || controller != oldWidget.controller;
}
