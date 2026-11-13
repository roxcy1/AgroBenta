import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../models/user.dart';
import '../../../repositories/auth_repository.dart';
import '../../../services/google_sign_in_service.dart';
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
  AuthController(this._repository, {GoogleSignInService? googleSignIn})
    : _googleSignIn = googleSignIn ?? GoogleSignInService();

  final AuthRepository _repository;
  final GoogleSignInService _googleSignIn;

  /// True while Google's account picker is open, before [_submit] takes over.
  bool _choosingGoogleAccount = false;

  AuthState _state = const AuthState.initial();
  AuthState get state => _state;

  /// Invalidates authentication reads and writes started by an earlier
  /// session. A response belongs to the session that launched it, not simply
  /// to whichever user happens to be signed in when it completes.
  int _sessionGeneration = 0;

  /// Checks for a stored session and, if there is one, loads the current user.
  ///
  /// Called once when the app starts. A missing or revoked token lands on
  /// [AuthStatus.signedOut]; a transport failure lands on
  /// [AuthStatus.restoreFailed] so the user is offered a retry instead of
  /// being silently signed out.
  Future<void> restoreSession() async {
    final int generation = _sessionGeneration;
    // The first call usually starts from `restoring` already. Re-announcing
    // that would notify listeners for no change — and when the first call comes
    // from `didChangeDependencies`, a synchronous notification would land
    // during the build phase and break the framework.
    if (_state.status != AuthStatus.restoring) {
      _set(_state.copyWith(status: AuthStatus.restoring, clearError: true));
    }

    try {
      final User? user = await _repository.restoreSession();
      if (generation != _sessionGeneration) {
        return;
      }
      _set(
        user == null
            ? const AuthState(status: AuthStatus.signedOut)
            : AuthState(status: AuthStatus.signedIn, user: user),
      );
    } on ApiException catch (error) {
      if (generation != _sessionGeneration) {
        return;
      }
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
  /// the form to render, and `false` is returned. With [remember] false
  /// ("Remember me" unticked) the session ends when the app is closed.
  Future<bool> signIn({
    required String email,
    required String password,
    bool remember = true,
  }) {
    return _submit(
      () => _repository.login(
        email: email,
        password: password,
        remember: remember,
      ),
    );
  }

  /// Whether the Google button should be offered on this device and build.
  bool get isGoogleSignInAvailable => _googleSignIn.isAvailable;

  /// Signs in with Google. An unknown email gets a new buyer account; an
  /// existing account with the same email is signed in.
  ///
  /// Returns `true` on success. Cancelling Google's account picker returns
  /// `false` without an error message. [remember] works as in [signIn].
  Future<bool> signInWithGoogle({bool remember = true}) async {
    if (_choosingGoogleAccount || _state.isSubmitting || _state.isSigningOut) {
      return false;
    }

    final String? idToken;
    _choosingGoogleAccount = true;
    try {
      idToken = await _googleSignIn.obtainIdToken();
    } on Object catch (error) {
      // Google's own reason (e.g. a SHA-1 / OAuth client mismatch) is only
      // useful to a developer, so it goes to the debug console, not the UI.
      debugPrint('Google sign-in failed: $error');
      _set(
        AuthState(
          status: AuthStatus.signedOut,
          errorMessage: googleSignInErrorMessage,
        ),
      );
      return false;
    } finally {
      _choosingGoogleAccount = false;
    }

    if (idToken == null || idToken.isEmpty) {
      return false;
    }

    return _submit(
      () => _repository.loginWithGoogle(idToken: idToken!, remember: remember),
    );
  }

  /// Shown when Google itself could not provide an account.
  static const String googleSignInErrorMessage =
      'Google sign-in could not be completed. Please try again.';

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

    final int generation = _sessionGeneration;
    final int requestingUserId = _state.user!.id;

    try {
      final User user = await _repository.refreshUser();
      if (generation != _sessionGeneration ||
          !_state.isSignedIn ||
          _state.user?.id != requestingUserId ||
          user.id != requestingUserId) {
        return false;
      }
      _set(AuthState(status: AuthStatus.signedIn, user: user));
      return true;
    } on ApiException catch (error) {
      if (generation != _sessionGeneration ||
          !_state.isSignedIn ||
          _state.user?.id != requestingUserId) {
        return false;
      }
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
    if (_state.isSigningOut || !_state.isSignedIn) {
      return false;
    }

    // Invalidate account refreshes immediately, before waiting for the revoke
    // request. None may republish the outgoing user's identity after logout.
    final int generation = ++_sessionGeneration;

    _set(_state.copyWith(isSigningOut: true, clearError: true));

    try {
      await _repository.logout();
      if (generation != _sessionGeneration) {
        return false;
      }
      _set(const AuthState(status: AuthStatus.signedOut));
      return true;
    } on ApiException catch (error) {
      if (generation != _sessionGeneration) {
        return false;
      }
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
    final int generation = ++_sessionGeneration;
    await _repository.forgetLocalSession();
    if (generation != _sessionGeneration) {
      return;
    }
    _set(const AuthState(status: AuthStatus.signedOut));
  }

  /// Asks the server to email a password reset code.
  ///
  /// Like [resetPassword], this leaves [state] alone: the device stays signed
  /// out either way, so the screen holds its own progress and error, and a
  /// failure cannot appear on the sign-in form later. Throws on failure; turn
  /// the error into text with [passwordResetErrorMessage].
  Future<void> requestPasswordReset({required String email}) =>
      _repository.forgotPassword(email: email);

  /// Sets a new password from an emailed reset code.
  Future<void> resetPassword({
    required String email,
    required String code,
    required String password,
    required String passwordConfirmation,
  }) {
    return _repository.resetPassword(
      email: email,
      code: code,
      password: password,
      passwordConfirmation: passwordConfirmation,
    );
  }

  /// The text to show for a failed password reset request.
  static String passwordResetErrorMessage(Object error) {
    if (error is! ApiException) {
      return 'Something went wrong. Please try again.';
    }
    return error.kind == ApiErrorKind.rateLimited
        ? 'Too many attempts. Please try again in a minute.'
        : error.message;
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
    if (_state.isSubmitting || _state.isSigningOut) {
      return false;
    }

    final int generation = ++_sessionGeneration;

    _set(
      _state.copyWith(
        isSubmitting: true,
        clearError: true,
        validationErrors: const {},
      ),
    );

    try {
      final User user = await action();
      if (generation != _sessionGeneration) {
        return false;
      }
      _set(AuthState(status: AuthStatus.signedIn, user: user));
      return true;
    } on ApiException catch (error) {
      if (generation != _sessionGeneration) {
        return false;
      }
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
      if (generation != _sessionGeneration) {
        return false;
      }
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
