import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../state/auth_scope.dart';
import '../state/auth_state.dart';
import '../widgets/auth_error_banner.dart';
import '../widgets/auth_form_scaffold.dart';
import 'auth_validators.dart';

/// `POST /auth/login`.
///
/// Email and password only. There is no "forgot password", no social sign-in
/// and no role choice: this app has one account per person, so there is one
/// way in and no way to pick a different kind of user here.
class SignInScreen extends StatefulWidget {
  const SignInScreen({required this.onRegister, super.key});

  /// Switches to the registration form.
  final VoidCallback onRegister;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

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
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final bool signedIn = await AuthScope.of(
      context,
    ).signIn(email: _email.text.trim(), password: _password.text);

    if (!signedIn && mounted) {
      _password.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AuthState state = AuthScope.of(context).state;

    return AuthFormScaffold(
      title: 'Sign in',
      heading: 'Welcome back',
      isSubmitting: state.isSubmitting,
      submitLabel: 'Sign in',
      onSubmit: _submit,
      fields: <Widget>[
        if (state.errorMessage != null) ...<Widget>[
          AuthErrorBanner(message: state.errorMessage!),
          const SizedBox(height: AppSpacing.lg),
        ],
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[AutofillHints.email],
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (String? value) =>
                    // A server 422 for this field outranks the local check: it
                    // is the authority on, say, an address that is already
                    // registered.
                    validateRequiredEmail(value) ?? state.errorFor('email'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _password,
                obscureText: true,
                textInputAction: TextInputAction.done,
                autofillHints: const <String>[AutofillHints.password],
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(labelText: 'Password'),
                validator: validateRequiredPassword,
              ),
            ],
          ),
        ),
      ],
      footer: TextButton(
        onPressed: state.isSubmitting ? null : widget.onRegister,
        child: const Text('Create an account'),
      ),
    );
  }
}
