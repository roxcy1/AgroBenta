import 'package:flutter/widgets.dart';

import '../../../repositories/offer_repository.dart';

/// The purchase-offer repository, for the offer screens and chat panel.
///
/// A plain [InheritedWidget] exposing the repository **only**. Making an offer
/// is a one-shot form and the chat's offer list is per-screen state, so each
/// screen creates and disposes its own controller. Nothing about an offer is
/// session state worth keeping alive after the route is popped.
///
/// Installed above `MaterialApp` in `main.dart`, so the pushed make-offer
/// screen and the chat panel can resolve it from any route.
class OfferScope extends InheritedWidget {
  const OfferScope({required this.repository, required super.child, super.key});

  final OfferRepository repository;

  /// The repository, registering [context] as a dependency.
  ///
  /// Correct from `build` and below. Calling it during `initState` throws —
  /// use [readOf] there.
  static OfferRepository of(BuildContext context) {
    final OfferScope? scope = context
        .dependOnInheritedWidgetOfExactType<OfferScope>();
    assert(scope != null, 'No OfferScope found in context.');
    return scope!.repository;
  }

  /// The repository, **without** registering a dependency. For `initState`.
  static OfferRepository readOf(BuildContext context) {
    final OfferScope? scope = context
        .getInheritedWidgetOfExactType<OfferScope>();
    assert(scope != null, 'No OfferScope found in context.');
    return scope!.repository;
  }

  @override
  bool updateShouldNotify(OfferScope oldWidget) =>
      repository != oldWidget.repository;
}
