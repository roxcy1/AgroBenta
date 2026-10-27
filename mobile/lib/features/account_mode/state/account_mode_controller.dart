import 'package:flutter/foundation.dart';

import '../../../models/user.dart';
import '../../auth/state/auth_controller.dart';
import 'account_mode.dart';

/// Keeps the selected Account Mode in sync with the authenticated account.
///
/// Every session starts in [AccountMode.buyer]. A verified seller may switch to
/// [AccountMode.seller] for as long as the server-granted capability lasts.
/// Signing out, changing accounts, or losing seller capability clears the
/// selection so another account can never inherit it.
class AccountModeController extends ChangeNotifier {
  AccountModeController(this._authController)
    : _lastUserId = _authController.state.user?.id {
    _authController.addListener(_syncWithAuth);
    _syncWithAuth();
  }

  final AuthController _authController;

  AccountMode _mode = AccountMode.buyer;
  int? _lastUserId;

  AccountMode get mode => _mode;

  /// Whether the authenticated account has server-granted seller capability.
  bool get canUseSellerMode => _authController.state.user?.isSeller ?? false;

  /// Selects [next], ignoring Seller Mode when the account cannot use it.
  void select(AccountMode next) {
    if (next == _mode) {
      return;
    }
    if (next == AccountMode.seller && !canUseSellerMode) {
      return;
    }
    _mode = next;
    notifyListeners();
  }

  void _syncWithAuth() {
    final User? user = _authController.state.user;
    final int? userId = user?.id;
    final bool accountChanged = userId != _lastUserId;
    _lastUserId = userId;

    if (user == null || !user.isSeller || accountChanged) {
      _selectBuyer();
    }
  }

  void _selectBuyer() {
    if (_mode == AccountMode.buyer) {
      return;
    }
    _mode = AccountMode.buyer;
    notifyListeners();
  }

  @override
  void dispose() {
    _authController.removeListener(_syncWithAuth);
    super.dispose();
  }
}
