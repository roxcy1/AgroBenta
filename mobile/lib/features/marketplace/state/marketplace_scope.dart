import 'package:flutter/widgets.dart';

import '../../../repositories/marketplace_repository.dart';
import 'marketplace_controller.dart';

/// Publishes the marketplace's long-lived dependencies to the widget tree.
///
/// A plain [InheritedWidget] carrying the [repository] and the list [controller],
/// installed once in `main.dart` above the buyer shell. Two accessors' worth of
/// thing in one widget, because the two are the same lifetime: the repository
/// outlives the shell, and the controller is created and disposed with the
/// session.
///
/// It is deliberately **not** an `InheritedNotifier`. The marketplace list needs
/// to rebuild on every state change, and it gets that from a `ListenableBuilder`
/// bound to the controller directly — which rebuilds only the list, where an
/// inherited notifier would rebuild every dependent, the filter control and the
/// search field included, on every keystroke.
///
/// The detail screen reaches this from a route pushed *above* the shell and
/// takes only the [repository]. It is given a listing id and not a listing
/// object precisely so it has to re-fetch, and so its controller is per-screen
/// and disposed with it.
class MarketplaceScope extends InheritedWidget {
  const MarketplaceScope({
    required this.repository,
    required this.controller,
    required super.child,
    super.key,
  });

  /// Shared across the session. Safe to hand to a per-screen controller.
  final MarketplaceRepository repository;

  /// Owns the marketplace list's state for the whole signed-in session, so
  /// navigating to a listing and back does not discard loaded pages or the
  /// scroll position.
  final MarketplaceController controller;

  /// The scope, for reading [repository] without touching [controller].
  ///
  /// Subscribes the caller to changes in the scope itself, which only happens if
  /// the repository or controller is replaced. Use this from `build`.
  static MarketplaceScope of(BuildContext context) {
    final MarketplaceScope? scope = context
        .dependOnInheritedWidgetOfExactType<MarketplaceScope>();
    assert(scope != null, 'No MarketplaceScope found above this widget.');
    return scope!;
  }

  /// The scope, **without** registering a dependency.
  ///
  /// For `initState` and `didChangeDependencies`, where
  /// `dependOnInheritedWidgetOfExactType` is not allowed — it throws, because
  /// the element is not yet active for ancestor lookups. Both the list and the
  /// detail screen resolve their dependencies in `initState` and then bind
  /// themselves to the controller with a [ListenableBuilder], so subscribing to
  /// the scope would buy nothing and assert.
  static MarketplaceScope readOf(BuildContext context) {
    final MarketplaceScope? scope = context
        .getInheritedWidgetOfExactType<MarketplaceScope>();
    assert(scope != null, 'No MarketplaceScope found above this widget.');
    return scope!;
  }

  @override
  bool updateShouldNotify(MarketplaceScope oldWidget) =>
      !identical(repository, oldWidget.repository) ||
      !identical(controller, oldWidget.controller);
}
