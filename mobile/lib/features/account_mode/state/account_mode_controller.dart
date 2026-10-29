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
  String? _notice;
  bool _rechecking = false;

  AccountMode get mode => _mode;

  /// Whether the authenticated account has server-granted seller capability.
  bool get canUseSellerMode => _authController.state.user?.isSeller ?? false;

  /// Returns the pending message for the user and clears it, without notifying.
  ///
  /// Set when Seller Mode was refused or dropped, so the app can say why
  /// instead of silently showing the buyer view.
  String? takeNotice() {
    final String? notice = _notice;
    _notice = null;
    return notice;
  }

  /// Switches to Seller Mode after asking the server whether the account is
  /// still a verified seller.
  ///
  /// The cached user can be stale — seller rights may have been removed after
  /// sign-in — so the capability is re-read from `/auth/me` first. If it cannot
  /// be confirmed, or the server says the account is not a seller, the mode is
  /// left alone and [takeNotice] explains why.
  Future<void> requestSellerMode() async {
    if (_mode == AccountMode.seller) {
      return;
    }
    if (!await _authController.refreshUser()) {
      _notice = 'Could not confirm your seller status. Please try again.';
      notifyListeners();
      return;
    }
    if (!canUseSellerMode) {
      _notice = 'Seller Mode is only available to verified sellers.';
      notifyListeners();
      return;
    }
    select(AccountMode.seller);
  }

  /// Re-reads the account from the server so a lost seller capability is
  /// noticed. A refresh that shows the account is no longer a seller drops
  /// Seller Mode through [_syncWithAuth].
  ///
  /// Used when the app resumes and when the server answers `403`. A request
  /// already in flight is not repeated, which also stops a `403` from the
  /// refresh itself looping back here.
  Future<void> recheckSellerCapability() async {
    if (_rechecking) {
      return;
    }
    _rechecking = true;
    try {
      await _authController.refreshUser();
    } finally {
      _rechecking = false;
    }
  }

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
      if (_mode == AccountMode.seller && user != null && !accountChanged) {
        _notice =
            'Your account is no longer a verified seller. '
            'Switched to Buyer Mode.';
      }
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
