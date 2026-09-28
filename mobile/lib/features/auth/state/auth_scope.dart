import 'package:flutter/widgets.dart';

import 'auth_controller.dart';

/// Makes the single [AuthController] available to the widget tree and rebuilds
/// dependents whenever it changes.
///
/// This is the Flutter SDK's own `InheritedNotifier`, so it costs no
/// dependency. `InheritedWidget` is how `Theme` and `MediaQuery` work; the app
/// needed one of those for a long-lived object, and the alternative — a
/// state-management package — is not justified until there is more than one
/// long-lived object to share.
class AuthScope extends InheritedNotifier<AuthController> {
  const AuthScope({
    required AuthController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  /// The controller, subscribing the calling widget to its changes.
  ///
  /// Use this in `build` when the widget renders authentication state.
  static AuthController of(BuildContext context) {
    final AuthScope? scope = context
        .dependOnInheritedWidgetOfExactType<AuthScope>();
    assert(scope != null, 'No AuthScope found above this widget.');
    return scope!.notifier!;
  }
}
