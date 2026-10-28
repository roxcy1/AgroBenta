import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../widgets/auth_error_banner.dart';
import '../widgets/auth_form_scaffold.dart';
import 'auth_validators.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, required this.onBackToSignIn});

  final VoidCallback onBackToSignIn;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  bool _submitting = false;
  String? _message;
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _submitting = true;
      _message = null;
    });

    await Future<void>.delayed(const Duration(milliseconds: 250));

    if (!mounted) {
      return;
    }

    setState(() {
      _submitting = false;
      _sent = true;
      _message =
          'If an account with that email exists, a password reset link has been sent.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuthFormScaffold(
      title: 'Forgot password',
      heading: 'Reset your password',
      isSubmitting: _submitting,
      submitLabel: _sent ? 'Back to sign in' : 'Send reset link',
      onSubmit: _sent ? widget.onBackToSignIn : _submit,
      fields: <Widget>[
        if (_message != null) ...<Widget>[
          AuthErrorBanner(message: _message!),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (!_sent)
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
          )
        else
          const Text(
            'Check your email for a reset link or code. If you don\'t see it, check your spam folder.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
      ],
      footer: TextButton(
        onPressed: _submitting ? null : widget.onBackToSignIn,
        child: const Text('Back to sign in'),
      ),
    );
  }
}
