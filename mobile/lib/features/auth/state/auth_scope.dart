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

  /// The controller, or `null` when there is no [AuthScope] above [context].
  ///
  /// For widgets that can render without a session — a screen mounted alone in
  /// a test, or a sub-tree that only degrades when it needs the current user.
  /// The same shape as `MessagingScope`'s `of`/`readOf` pair: one accessor
  /// asserts, the other lets the caller decide what absence means.
  static AuthController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AuthScope>()?.notifier;
  }
}
