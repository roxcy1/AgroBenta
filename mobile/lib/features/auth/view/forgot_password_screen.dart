import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../state/auth_controller.dart';
import '../state/auth_scope.dart';
import '../widgets/auth_error_banner.dart';
import '../widgets/auth_form_scaffold.dart';
import 'auth_validators.dart';

/// `POST /auth/forgot-password`.
///
/// The reply is the same whether or not the email is registered, so this screen
/// moves on after any success and never suggests that an account exists.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({
    required this.onBackToSignIn,
    required this.onCodeRequested,
    super.key,
  });

  final VoidCallback onBackToSignIn;

  /// Called with the submitted email once the server has accepted the request.
  final ValueChanged<String> onCodeRequested;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final String email = _email.text.trim();

    try {
      await AuthScope.of(context).requestPasswordReset(email: email);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = AuthController.passwordResetErrorMessage(error);
        });
      }
      return;
    }

    if (mounted) {
      widget.onCodeRequested(email);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthFormScaffold(
      title: 'Forgot password',
      heading: 'Reset your password',
      isSubmitting: _submitting,
      submitLabel: 'Send reset code',
      onSubmit: _submit,
      fields: <Widget>[
        const Text(
          'Enter your email address and we will send you a code to reset your '
          'password.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_error != null) ...<Widget>[
          AuthErrorBanner(message: _error!),
          const SizedBox(height: AppSpacing.lg),
        ],
        Form(
          key: _formKey,
          child: TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const <String>[AutofillHints.email],
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Email'),
            validator: validateRequiredEmail,
            onFieldSubmitted: (_) => _submit(),
          ),
        ),
      ],
      footer: TextButton(
        onPressed: _submitting ? null : widget.onBackToSignIn,
        child: const Text('Back to sign in'),
      ),
    );
  }
}
