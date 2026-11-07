import 'package:flutter/material.dart';

import '../state/auth_controller.dart';
import '../state/auth_scope.dart';
import '../state/auth_state.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';
import 'reset_password_screen.dart';
import 'session_status_screens.dart';
import 'sign_in_screen.dart';

/// Routes between the signed-out and signed-in parts of the app from a single
/// piece of state.
///
/// One gate, no navigation package. `go_router` earns its place when there are
/// pushed routes, deep links and nested navigators; M1 has one destination per
/// state, so a switch is both simpler and easier to reason about.
///
/// The session check starts here rather than in `main.dart` because it needs a
/// mounted widget, and `didChangeDependencies` is the first point at which an
/// inherited controller can be read.
class AuthGate extends StatefulWidget {
  const AuthGate({required this.authenticatedView, super.key});

  /// The signed-in destination. Supplied by the composition root so this
  /// feature does not depend on the feature it hands off to.
  final WidgetBuilder authenticatedView;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  /// Which form a signed-out user is looking at. View state, not auth state:
  /// it means nothing to the server and must not survive a sign-out.
  bool _showRegistration = false;
  bool _showForgotPassword = false;

  /// The email a reset code was requested for. Set while the reset form shows.
  String? _resetEmail;

  /// A confirmation for the sign-in form, set after a password reset.
  String? _signInNotice;

  bool _restoreStarted = false;
  bool _wasSignedIn = false;
  int? _lastUserId;
  AuthController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final AuthController controller = AuthScope.of(context);
    if (_controller != controller) {
      _controller?.removeListener(_handleAuthChanged);
      _controller = controller..addListener(_handleAuthChanged);
    }

    if (!_restoreStarted) {
      _restoreStarted = true;
      // Started after the frame rather than inline: `didChangeDependencies`
      // runs during the build phase, and kicking off request work from inside
      // it is how you end up notifying listeners mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          controller.restoreSession();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_handleAuthChanged);
    super.dispose();
  }

  /// Landing on the sign-in form after a sign-out, rather than wherever the
  /// user happened to be, is the expected behaviour.
  void _handleAuthChanged() {
    final AuthState state = _controller!.state;
    final bool signedIn = state.isSignedIn;
    final int? userId = signedIn ? state.user?.id : null;
    final bool statusChanged = signedIn != _wasSignedIn;
    final bool identityChanged =
        _wasSignedIn && signedIn && userId != _lastUserId;
    final bool sessionEnded = (_wasSignedIn && !signedIn) || identityChanged;

    _wasSignedIn = signedIn;
    _lastUserId = userId;
    if (sessionEnded) {
      // Pushed detail/form routes are siblings of AuthGate in the Navigator.
      // Pop them on logout or account replacement so Back cannot reveal a
      // screen built under the previous user's session.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(
            context,
            rootNavigator: true,
          ).popUntil((Route<dynamic> route) => route.isFirst);
        }
      });
    }

    if (statusChanged) {
      if (!signedIn) {
        if (_showRegistration || _showForgotPassword || _resetEmail != null) {
          _showSignIn();
        }
      } else {
        _signInNotice = null;
      }
    } else if (identityChanged) {
      _signInNotice = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AuthState state = AuthScope.of(context).state;

    return switch (state.status) {
      AuthStatus.restoring => const RestoringSessionScreen(),
      AuthStatus.restoreFailed => RestoreFailedScreen(state: state),
      AuthStatus.signedOut =>
        _resetEmail != null
            ? ResetPasswordScreen(
                email: _resetEmail!,
                onBackToSignIn: _showSignIn,
                onPasswordReset: _finishPasswordReset,
              )
            : _showForgotPassword
            ? ForgotPasswordScreen(
                onBackToSignIn: _showSignIn,
                onCodeRequested: _goToResetPassword,
              )
            : _showRegistration
            ? RegisterScreen(onSignIn: _showSignIn)
            : SignInScreen(
                onRegister: _showRegister,
                onForgotPassword: _goToForgotPassword,
                notice: _signInNotice,
              ),
      AuthStatus.signedIn => KeyedSubtree(
        // Rebuild the complete tab shell when an authenticated identity
        // changes without an intervening signed-out frame.
        key: ValueKey<int>(state.user!.id),
        child: Builder(builder: widget.authenticatedView),
      ),
    };
  }

  void _showRegister() => setState(() {
    _showRegistration = true;
    _showForgotPassword = false;
    _signInNotice = null;
  });

  void _goToForgotPassword() => setState(() {
    _showForgotPassword = true;
    _showRegistration = false;
    _signInNotice = null;
  });

  void _goToResetPassword(String email) => setState(() {
    _resetEmail = email;
  });

  void _finishPasswordReset() {
    _showSignIn();
    setState(() {
      _signInNotice =
          'Your password has been reset. Sign in with your new password.';
    });
  }

  void _showSignIn() => setState(() {
    _showRegistration = false;
    _showForgotPassword = false;
    _resetEmail = null;
  });
}
