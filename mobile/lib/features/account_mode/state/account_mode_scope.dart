import 'package:flutter/widgets.dart';

import 'account_mode_controller.dart';

/// Makes the session's [AccountModeController] available to the widget tree.
///
/// An [InheritedNotifier], like `AuthScope`, so widgets that render the current
/// mode rebuild when it changes.
class AccountModeScope extends InheritedNotifier<AccountModeController> {
  const AccountModeScope({
    required AccountModeController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static AccountModeController of(BuildContext context) {
    final AccountModeScope? scope = context
        .dependOnInheritedWidgetOfExactType<AccountModeScope>();
    assert(scope != null, 'No AccountModeScope found above this widget.');
    return scope!.notifier!;
  }
}
