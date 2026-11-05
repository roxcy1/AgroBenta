import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/user.dart';
import '../../auth/state/auth_controller.dart';
import 'account_mode_preference_store.dart';
import 'account_mode.dart';

/// Keeps the selected Account Mode in sync with the authenticated account.
///
/// Each account's last selected mode is persisted independently. Seller Mode is
/// restored only when the server-confirmed user still has seller capability.
class AccountModeController extends ChangeNotifier {
  AccountModeController(this._authController, {this.preferenceStore}) {
    _authController.addListener(_syncWithAuth);
    _syncWithAuth();
  }

  final AuthController _authController;
  final AccountModePreferenceStore? preferenceStore;

  AccountMode _mode = AccountMode.buyer;
  int? _lastUserId;
  String? _notice;
  bool _rechecking = false;
  bool _isRestoringPreference = false;
  bool _disposed = false;
  int _preferenceGeneration = 0;
  Future<void> _pendingWrites = Future<void>.value();

  AccountMode get mode => _mode;
  bool get isRestoringPreference => _isRestoringPreference;

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
    if (_mode == AccountMode.seller || _isRestoringPreference) {
      return;
    }
    final int? requestingUserId = _authController.state.user?.id;
    if (requestingUserId == null || !_authController.state.isSignedIn) {
      return;
    }
    if (!await _authController.refreshUser()) {
      if (!_isCurrentUser(requestingUserId)) return;
      _notice = 'Could not confirm your seller status. Please try again.';
      notifyListeners();
      return;
    }
    if (!_isCurrentUser(requestingUserId)) return;
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
    if (next == _mode ||
        _isRestoringPreference ||
        !_authController.state.isSignedIn) {
      return;
    }
    if (next == AccountMode.seller && !canUseSellerMode) {
      return;
    }
    _mode = next;
    notifyListeners();
    final int? userId = _authController.state.user?.id;
    if (userId != null) {
      _persistPreference(userId, next);
    }
  }

  void _syncWithAuth() {
    final User? user = _authController.state.isSignedIn
        ? _authController.state.user
        : null;
    final int? userId = user?.id;
    final bool accountChanged = userId != _lastUserId;

    if (accountChanged) {
      _lastUserId = userId;
      final int generation = ++_preferenceGeneration;
      _notice = null;
      _mode = AccountMode.buyer;
      _isRestoringPreference = user != null && preferenceStore != null;
      notifyListeners();
      if (user != null && preferenceStore != null) {
        unawaited(_restorePreference(user.id, generation));
      }
      return;
    }

    if (user == null) {
      _isRestoringPreference = false;
      _selectBuyer();
      return;
    }

    if (!user.isSeller) {
      if (_mode == AccountMode.seller) {
        _notice =
            'Your account is no longer a verified seller. '
            'Switched to Buyer Mode.';
      }
      _selectBuyer();
    }
  }

  Future<void> _restorePreference(int userId, int generation) async {
    AccountMode restoredMode = AccountMode.buyer;
    final AccountModePreferenceStore? store = preferenceStore;
    if (store == null) return;

    try {
      // If the same account changed mode just before logout, finish those
      // serialized writes before reading its preference on the next sign-in.
      await _pendingWrites;
      final String? saved = await store.read(userId);
      final User? currentUser = _authController.state.user;
      if (saved == AccountMode.seller.name && currentUser?.isSeller == true) {
        restoredMode = AccountMode.seller;
      }
    } on Object {
      // A storage read failure safely leaves the account in Buyer Mode.
    }

    if (_disposed ||
        generation != _preferenceGeneration ||
        !_isCurrentUser(userId)) {
      return;
    }

    _mode = restoredMode;
    _isRestoringPreference = false;
    notifyListeners();
  }

  void _persistPreference(int userId, AccountMode mode) {
    final AccountModePreferenceStore? store = preferenceStore;
    if (store == null) return;

    _pendingWrites = _writeAfter(_pendingWrites, store, userId, mode);
    unawaited(_pendingWrites);
  }

  Future<void> _writeAfter(
    Future<void> previous,
    AccountModePreferenceStore store,
    int userId,
    AccountMode mode,
  ) async {
    try {
      await previous;
    } on Object {
      // Continue the queue after a failed earlier write.
    }
    try {
      await store.write(userId, mode.name);
    } on Object {
      // The current session remains usable if local preference storage fails.
    }
  }

  bool _isCurrentUser(int userId) =>
      _authController.state.isSignedIn &&
      _authController.state.user?.id == userId;

  void _selectBuyer() {
    if (_mode == AccountMode.buyer) {
      return;
    }
    _mode = AccountMode.buyer;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _preferenceGeneration++;
    _authController.removeListener(_syncWithAuth);
    super.dispose();
  }
}
