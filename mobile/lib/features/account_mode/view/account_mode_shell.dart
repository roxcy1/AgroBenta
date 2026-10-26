import 'package:flutter/material.dart';

import '../../buyer_shell/view/buyer_shell.dart';
import '../../seller_shell/view/seller_shell.dart';
import '../state/account_mode.dart';
import '../state/account_mode_controller.dart';
import '../state/account_mode_scope.dart';

/// The signed-in destination for the selected Account Mode.
///
/// Reading [AccountModeScope] registers a dependency, so changing the mode in
/// Profile replaces the whole shell on the next frame. Seller Mode is guarded
/// twice: the controller refuses the selection without server-granted seller
/// capability, and this switch falls back to the buyer shell if the two ever
/// disagree. The mode itself never grants anything; the backend authorises
/// every seller request from `seller_capability`.
class AccountModeShell extends StatelessWidget {
  const AccountModeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final AccountModeController controller = AccountModeScope.of(context);
    final bool showSeller =
        controller.mode == AccountMode.seller && controller.canUseSellerMode;

    return showSeller ? const SellerShell() : const BuyerShell();
  }
}
