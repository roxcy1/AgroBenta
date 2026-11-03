import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_spacing.dart';
import '../state/auth_controller.dart';
import '../state/auth_scope.dart';
import '../widgets/auth_error_banner.dart';
import '../widgets/auth_form_scaffold.dart';
import '../widgets/auth_notice_banner.dart';
import 'auth_validators.dart';

/// `POST /auth/reset-password`.
///
/// The emailed code, a new password and its confirmation. A successful reset
/// creates no session: the server has revoked every token the account held, so
/// the user returns to sign in with the new password.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({
    required this.email,
    required this.onBackToSignIn,
    required this.onPasswordReset,
    super.key,
  });

  /// The address the code was requested for.
  final String email;

  final VoidCallback onBackToSignIn;
  final VoidCallback onPasswordReset;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _code = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirmPassword = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    _confirmPassword.dispose();
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

    try {
      await AuthScope.of(context).resetPassword(
        email: widget.email,
        code: _code.text.trim(),
        password: _password.text,
        passwordConfirmation: _confirmPassword.text,
      );
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
      widget.onPasswordReset();
    }
  }

  String? _validateConfirmation(String? value) {
    if (value == null || value.isEmpty) {
      return 'Confirm your new password.';
    }
    return value == _password.text ? null : 'The passwords do not match.';
  }

  Widget _visibilityToggle({
    required bool obscured,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(
        obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      ),
      tooltip: obscured ? 'Show password' : 'Hide password',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthFormScaffold(
      title: 'Reset password',
      heading: 'Enter your reset code',
      isSubmitting: _submitting,
      submitLabel: 'Reset password',
      onSubmit: _submit,
      fields: <Widget>[
        AuthNoticeBanner(
          message:
              'If an account exists for ${widget.email}, we sent it a '
              '$resetCodeLength-digit code. If you do not see it, check your '
              'spam folder.',
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_error != null) ...<Widget>[
          AuthErrorBanner(message: _error!),
          const SizedBox(height: AppSpacing.lg),
        ],
        Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextFormField(
                controller: _code,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[AutofillHints.oneTimeCode],
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(resetCodeLength),
                ],
                decoration: const InputDecoration(labelText: 'Reset code'),
                validator: validateResetCode,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _password,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'New password',
                  suffixIcon: _visibilityToggle(
                    obscured: _obscurePassword,
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: validatePasswordLength,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _confirmPassword,
                obscureText: _obscureConfirmation,
                textInputAction: TextInputAction.done,
                autofillHints: const <String>[AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'Confirm new password',
                  suffixIcon: _visibilityToggle(
                    obscured: _obscureConfirmation,
                    onPressed: () => setState(
                      () => _obscureConfirmation = !_obscureConfirmation,
                    ),
                  ),
                ),
                validator: _validateConfirmation,
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
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
