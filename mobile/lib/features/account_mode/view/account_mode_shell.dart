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
///
/// While in Seller Mode, resuming the app re-reads the account from the server,
/// so seller rights removed in the meantime are noticed. Any message the
/// controller leaves for the user is shown here, above whichever shell is
/// current.
class AccountModeShell extends StatefulWidget {
  const AccountModeShell({super.key});

  @override
  State<AccountModeShell> createState() => _AccountModeShellState();
}

class _AccountModeShellState extends State<AccountModeShell>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }
    final AccountModeController controller = AccountModeScope.of(context);
    if (controller.mode == AccountMode.seller) {
      controller.recheckSellerCapability();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AccountModeController controller = AccountModeScope.of(context);
    final bool showSeller =
        controller.mode == AccountMode.seller && controller.canUseSellerMode;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final String? notice = controller.takeNotice();
      if (notice != null && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(notice)));
      }
    });

    return showSeller ? const SellerShell() : const BuyerShell();
  }
}
