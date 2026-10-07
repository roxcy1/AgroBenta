import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../models/user.dart';
import '../../../repositories/auth_repository.dart';
import 'auth_state.dart';

/// Presentation logic for authentication.
///
/// The only thing that mutates [state]. Screens call these methods and listen;
/// they never touch `AuthRepository` or `ApiClient` themselves.
///
/// Errors are translated once, here, so that no screen has to reason about
/// [ApiErrorKind]. A `401`, a `422`, a `429` and an unreachable server all end
/// up as a message the user can act on, because [ApiException.message] is
/// already curated to be displayable.
class AuthController extends ChangeNotifier {
  AuthController(this._repository);

  final AuthRepository _repository;

  AuthState _state = const AuthState.initial();
  AuthState get state => _state;

  /// Checks for a stored session and, if there is one, loads the current user.
  ///
  /// Called once when the app starts. A missing or revoked token lands on
  /// [AuthStatus.signedOut]; a transport failure lands on
  /// [AuthStatus.restoreFailed] so the user is offered a retry instead of
  /// being silently signed out.
  Future<void> restoreSession() async {
    // The first call usually starts from `restoring` already. Re-announcing
    // that would notify listeners for no change — and when the first call comes
    // from `didChangeDependencies`, a synchronous notification would land
    // during the build phase and break the framework.
    if (_state.status != AuthStatus.restoring) {
      _set(_state.copyWith(status: AuthStatus.restoring, clearError: true));
    }

    try {
      final User? user = await _repository.restoreSession();
      _set(
        user == null
            ? const AuthState(status: AuthStatus.signedOut)
            : AuthState(status: AuthStatus.signedIn, user: user),
      );
    } on ApiException catch (error) {
      _set(
        _state.copyWith(
          status: AuthStatus.restoreFailed,
          errorMessage: error.message,
        ),
      );
    }
  }

  /// Signs in with [email] and [password].
  ///
  /// Returns `true` on success. On failure the error is left in [state] for
  /// the form to render, and `false` is returned.
  Future<bool> signIn({required String email, required String password}) {
    return _submit(() => _repository.login(email: email, password: password));
  }

  /// Registers a buyer account and signs the new user in.
  Future<bool> register({
    required String name,
    required String email,
    required String password,
    required String passwordConfirmation,
  }) {
    return _submit(
      () => _repository.register(
        name: name,
        email: email,
        password: password,
        passwordConfirmation: passwordConfirmation,
      ),
    );
  }

  /// Re-reads the signed-in user from the server and publishes it.
  ///
  /// Returns `true` when the refreshed user was published.
  ///
  /// Used after something the server owns has changed underneath a live session
  /// — chiefly an approved seller verification, which moves
  /// `seller_capability` to `seller`. The alternative would be telling the user
  /// their application was approved while the account card beside it still
  /// said "Buyer", which is only fixable by signing out and back in.
  ///
  /// Failure handling differs from [_submit] on purpose:
  ///
  ///  * A `401` signs the device out. `ApiClient` has already cleared the token,
  ///    so the session is genuinely gone and [AuthGate] should route to sign-in.
  ///  * Any **other** failure — offline, a `5xx`, a malformed body — leaves the
  ///    session exactly as it was and reports `false`. Signing someone out
  ///    because a refresh could not complete would throw away a working session
  ///    over a transient fault.
  ///
  /// The user is only replaced on success, so a failed refresh cannot blank the
  /// account details the UI is currently showing.
  Future<bool> refreshUser() async {
    if (_state.status != AuthStatus.signedIn) {
      return false;
    }

    try {
      final User user = await _repository.refreshUser();
      _set(AuthState(status: AuthStatus.signedIn, user: user));
      return true;
    } on ApiException catch (error) {
      if (error.requiresReauthentication) {
        _set(const AuthState(status: AuthStatus.signedOut));
      }
      return false;
    } on Object {
      return false;
    }
  }

  /// Revokes the session and returns to the sign-in form.
  ///
  /// Returns `true` once the device is signed out. A failure that leaves the
  /// token in place returns `false` with the error in [state], so the user can
  /// retry rather than being left in a half-signed-out state.
  Future<bool> signOut() async {
    if (_state.isSigningOut) {
      return false;
    }

    _set(_state.copyWith(isSigningOut: true, clearError: true));

    try {
      await _repository.logout();
      _set(const AuthState(status: AuthStatus.signedOut));
      return true;
    } on ApiException catch (error) {
      _set(_state.copyWith(isSigningOut: false, errorMessage: error.message));
      return false;
    }
  }

  /// Discards the stored token and returns to the sign-in form without
  /// contacting the server.
  ///
  /// Offered only from [AuthStatus.restoreFailed], where the API is
  /// unreachable and [signOut] could not complete. The server keeps a valid
  /// token the user has abandoned; it carries no capability the user cannot
  /// already exercise, and the alternative is being stuck on a retry screen
  /// with no way out.
  Future<void> forgetLocalSession() async {
    await _repository.forgetLocalSession();
    _set(const AuthState(status: AuthStatus.signedOut));
  }

  /// Discards the current error so a form can be retried cleanly.
  void clearError() {
    if (_state.errorMessage == null && _state.validationErrors.isEmpty) {
      return;
    }
    _set(_state.copyWith(clearError: true, validationErrors: const {}));
  }

  /// Runs an authenticated request, mapping success to a signed-in state and
  /// failure to a form-level error.
  Future<bool> _submit(Future<User> Function() action) async {
    if (_state.isSubmitting) {
      return false;
    }

    _set(
      _state.copyWith(
        isSubmitting: true,
        clearError: true,
        validationErrors: const {},
      ),
    );

    try {
      final User user = await action();
      _set(AuthState(status: AuthStatus.signedIn, user: user));
      return true;
    } on ApiException catch (error) {
      // A failed sign-in or registration means, unambiguously, that this
      // device is not authenticated. The state is rebuilt rather than copied so
      // no stale user survives it.
      _set(
        AuthState(
          status: AuthStatus.signedOut,
          errorMessage: error.message,
          validationErrors: error.validationErrors,
        ),
      );
      return false;
    } on Object {
      // An unexpected error must not crash the app or leave the button
      // spinning. There is no meaningful detail to show, so say so plainly.
      _set(
        const AuthState(
          status: AuthStatus.signedOut,
          errorMessage: 'Something went wrong. Please try again.',
        ),
      );
      return false;
    }
  }

  void _set(AuthState next) {
    _state = next;
    notifyListeners();
  }
}
