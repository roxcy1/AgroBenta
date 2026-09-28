import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../state/auth_controller.dart';
import '../state/auth_scope.dart';
import '../state/auth_state.dart';
import '../widgets/auth_error_banner.dart';

/// Shown while the app decides whether this device already has a session.
///
/// Deliberately not a spinner over the sign-in form: flashing the form and
/// then swapping it for the home screen reads as a glitch, and to a screen
/// reader it announces the wrong thing.
class RestoringSessionScreen extends StatelessWidget {
  const RestoringSessionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('AgroBenta')),
      body: SafeArea(
        child: Center(
          child: Semantics(
            label: 'Checking your session',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const CircularProgressIndicator(),
                const SizedBox(height: AppSpacing.md),
                Text('Checking your session', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when a stored session could not be verified because the API was
/// unreachable.
///
/// This is deliberately **not** the sign-in form. The token is probably still
/// valid; signing the user out because their connection dropped would be
/// wrong. So the screen offers a retry, and separately a way to abandon the
/// session on purpose.
class RestoreFailedScreen extends StatelessWidget {
  const RestoreFailedScreen({required this.state, super.key});

  final AuthState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AuthController controller = AuthScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('AgroBenta')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        'Could not sign you in',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'We could not check your saved session. Check your '
                        'connection and try again.',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (state.errorMessage != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.lg),
                        AuthErrorBanner(message: state.errorMessage!),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      FilledButton(
                        onPressed: controller.restoreSession,
                        child: const Text('Try again'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextButton(
                        onPressed: controller.forgetLocalSession,
                        child: const Text('Sign out instead'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
