import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../state/auth_scope.dart';
import '../state/auth_state.dart';
import '../widgets/auth_error_banner.dart';
import '../widgets/auth_form_scaffold.dart';
import 'auth_validators.dart';

/// `POST /auth/register`.
///
/// Name, email, password and its confirmation — and nothing else. There is no
/// role or "I want to sell" choice here, because every account starts as a
/// buyer and seller capability is granted by the server after seller
/// verification (a later phase, GAP-07). The account is signed in on success:
/// registering is a two-step-per-user process, not two places to manage
/// credentials.
///
/// The confirmation field is validated live rather than only on submit, because
/// a mismatch is knowable the moment the second field is filled in.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({required this.onSignIn, super.key});

  /// Switches back to the sign-in form.
  final VoidCallback onSignIn;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirmPassword = TextEditingController();

  /// The field errors currently on screen, so a repeat of the same server error
  /// does not re-validate for nothing.
  Map<String, List<String>> _displayedErrors = const <String, List<String>>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _revealServerFieldErrors(AuthScope.of(context).state.validationErrors);
  }

  /// A `TextFormField` runs its validator when its value changes and when
  /// `validate()` is called — not when the widget rebuilds. A `422` therefore
  /// arrives after the last validation and would never appear on the field
  /// without this.
  void _revealServerFieldErrors(Map<String, List<String>> errors) {
    if (mapEquals(errors, _displayedErrors)) {
      return;
    }
    _displayedErrors = Map<String, List<String>>.of(errors);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _formKey.currentState?.validate();
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    await AuthScope.of(context).register(
      name: _name.text.trim(),
      email: _email.text.trim(),
      password: _password.text,
      passwordConfirmation: _confirmPassword.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AuthState state = AuthScope.of(context).state;

    return AuthFormScaffold(
      title: 'Create account',
      heading: 'Create your account',
      isSubmitting: state.isSubmitting,
      submitLabel: 'Create account',
      onSubmit: _submit,
      fields: <Widget>[
        if (state.errorMessage != null) ...<Widget>[
          AuthErrorBanner(message: state.errorMessage!),
          const SizedBox(height: AppSpacing.lg),
        ],
        Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[AutofillHints.name],
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (String? value) {
                  final String local = value?.trim() ?? '';
                  if (local.isEmpty) {
                    return 'Enter your name.';
                  }
                  return local.length > 255
                      ? 'Your name must be 255 characters or fewer.'
                      : null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[AutofillHints.email],
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (String? value) =>
                    validateRequiredEmail(value) ?? state.errorFor('email'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _password,
                obscureText: true,
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[AutofillHints.newPassword],
                decoration: const InputDecoration(labelText: 'Password'),
                validator: (String? value) =>
                    validatePasswordLength(value) ?? state.errorFor('password'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _confirmPassword,
                obscureText: true,
                textInputAction: TextInputAction.done,
                autofillHints: const <String>[AutofillHints.newPassword],
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                ),
                validator: _validateConfirmation,
              ),
            ],
          ),
        ),
      ],
      footer: TextButton(
        onPressed: state.isSubmitting ? null : widget.onSignIn,
        child: const Text('I already have an account'),
      ),
    );
  }

  /// Checks the confirmation against the password field, which only the
  /// controller for that field can do.
  String? _validateConfirmation(String? value) {
    if (value == null || value.isEmpty) {
      return 'Confirm your password.';
    }
    if (value != _password.text) {
      return 'The passwords do not match.';
    }
    return null;
  }
}
