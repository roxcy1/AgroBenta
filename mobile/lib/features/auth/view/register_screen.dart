import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../state/auth_scope.dart';
import '../state/auth_state.dart';
import '../widgets/auth_error_banner.dart';
import '../widgets/auth_scenic_header.dart';
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
/// The layout follows `AgroBenta_Registration_DESIGN.md`: a branded landscape
/// hero overlapped by the white registration panel. Two things it specifies are
/// deliberately not backed by the API and are handled honestly here:
///
///  * **Consent** — `POST /auth/register` has no consent field, so the
///    Terms/Privacy acknowledgement is enforced **client-side only**. It is
///    required because the approved design specifies it, but the server neither
///    receives nor validates it.
///  * **Social sign-up** — the backend implements no Google/Facebook OAuth and
///    no credential exists, so the buttons are rendered disabled rather than
///    implying a capability that is not there.
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

  /// Password visibility, tracked independently for the two fields so revealing
  /// one does not reveal the other.
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;

  /// Consent to the Terms and Privacy Policy.
  ///
  /// Not a server field — the register endpoint carries none — so this is a
  /// client-side gate only. See the class doc.
  bool _agreedToTerms = false;
  String? _consentError;

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
    final bool formValid = _formKey.currentState?.validate() ?? false;
    final bool consentGiven = _agreedToTerms;

    if (!consentGiven) {
      setState(
        () => _consentError =
            'Please agree to the Terms and Privacy Policy to continue.',
      );
    }

    if (!formValid || !consentGiven) {
      return;
    }

    await AuthScope.of(context).register(
      name: _name.text.trim(),
      email: _email.text.trim(),
      password: _password.text,
      passwordConfirmation: _confirmPassword.text,
    );
  }

  void _setConsent(bool value) {
    if (_agreedToTerms == value && _consentError == null) {
      return;
    }
    setState(() {
      _agreedToTerms = value;
      if (value) {
        _consentError = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final AuthState state = AuthScope.of(context).state;
    final bool busy = state.isSubmitting;

    // The hero scales with the text scale so an enlarged brand block can never
    // overflow a fixed-height decoration, and is capped so it cannot swallow
    // the screen on a short device.
    final double textScale = MediaQuery.textScalerOf(
      context,
    ).scale(1).clamp(1.0, 1.8).toDouble();
    final double heroHeight =
        (MediaQuery.sizeOf(context).height * 0.30 * textScale)
            .clamp(200.0, 300.0)
            .toDouble();

    // How far the white panel rides up over the hero's bottom edge.
    const double overlap = 28;

    return Scaffold(
      backgroundColor: AppColors.background,
      // The header sits below the status bar rather than under it; the bottom
      // inset is applied inside the scroll content instead, so the panel can
      // run to the very bottom of the screen.
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  AuthScenicHeader(height: heroHeight),
                  Padding(
                    padding: EdgeInsets.only(top: heroHeight - overlap),
                    child: _buildPanel(context, state, busy),
                  ),
                ],
              ),
              SizedBox(
                height: MediaQuery.paddingOf(context).bottom + AppSpacing.md,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context, AuthState state, bool busy) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(24),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Center(
        child: ConstrainedBox(
          // A phone is narrower than this, so the constraint only matters on a
          // tablet or in landscape, where it stops the form stretching into
          // unreadable full-width fields.
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Create Your Account',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: AppSpacing.lg),
                if (state.errorMessage != null) ...<Widget>[
                  AuthErrorBanner(message: state.errorMessage!),
                  const SizedBox(height: AppSpacing.lg),
                ],
                _buildFields(state),
                const SizedBox(height: AppSpacing.lg),
                _buildConsent(busy),
                if (_consentError != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _consentError!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                FilledButton(
                  onPressed: busy ? null : _submit,
                  child: busy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Create Account'),
                ),
                const SizedBox(height: AppSpacing.xl),
                _buildDivider(theme),
                const SizedBox(height: AppSpacing.lg),
                _buildSocialRow(),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Social sign-up is not available yet.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.lg),
                _buildFooter(theme, state),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFields(AuthState state) {
    return Form(
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
            decoration: const InputDecoration(
              labelText: 'Full Name',
              prefixIcon: Icon(Icons.person_outline),
            ),
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
            decoration: const InputDecoration(
              labelText: 'Email Address',
              prefixIcon: Icon(Icons.mail_outline),
            ),
            validator: (String? value) =>
                validateRequiredEmail(value) ?? state.errorFor('email'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _password,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.next,
            autofillHints: const <String>[AutofillHints.newPassword],
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: _PasswordVisibilityToggle(
                visible: !_obscurePassword,
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: (String? value) =>
                validatePasswordLength(value) ?? state.errorFor('password'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _confirmPassword,
            obscureText: _obscureConfirmation,
            textInputAction: TextInputAction.done,
            autofillHints: const <String>[AutofillHints.newPassword],
            onFieldSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Confirm Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: _PasswordVisibilityToggle(
                visible: !_obscureConfirmation,
                onPressed: () =>
                    setState(() => _obscureConfirmation = !_obscureConfirmation),
              ),
            ),
            validator: _validateConfirmation,
          ),
        ],
      ),
    );
  }

  Widget _buildConsent(bool busy) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? linkStyle = theme.textTheme.bodyMedium?.copyWith(
      color: AppColors.primary,
      fontWeight: FontWeight.w700,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Checkbox(
          value: _agreedToTerms,
          onChanged: busy
              ? null
              : (bool? value) => _setConsent(value ?? false),
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: busy ? null : () => _setConsent(!_agreedToTerms),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text.rich(
                TextSpan(
                  style: theme.textTheme.bodyMedium,
                  children: <InlineSpan>[
                    const TextSpan(text: 'I agree to the '),
                    // Rendered as links visually, but deliberately not
                    // navigable: no approved Terms or Privacy destination
                    // exists, and the design forbids inventing URLs.
                    TextSpan(text: 'Terms', style: linkStyle),
                    const TextSpan(text: ' and '),
                    TextSpan(text: 'Privacy Policy', style: linkStyle),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDivider(ThemeData theme) {
    return Row(
      children: <Widget>[
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Text('or sign up with', style: theme.textTheme.bodySmall),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }

  Widget _buildSocialRow() {
    // Disabled, not absent: the buttons are part of the approved layout, but the
    // backend implements no OAuth. A disabled control states the feature is not
    // available; a working-looking one would imply it is.
    //
    // Each carries its provider's brand mark from Font Awesome. The colours are
    // the providers' brand identities, not part of the AgroBenta palette, so
    // they stay local to these two icons rather than entering `AppColors`.
    return const Row(
      children: <Widget>[
        Expanded(
          child: OutlinedButton(
            onPressed: null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                FaIcon(
                  FontAwesomeIcons.google,
                  size: 18,
                  color: Color(0xFF4285F4),
                ),
                SizedBox(width: AppSpacing.xs),
                Text('Google'),
              ],
            ),
          ),
        ),
        SizedBox(width: AppSpacing.md),
        Expanded(
          child: OutlinedButton(
            onPressed: null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                FaIcon(
                  FontAwesomeIcons.facebook,
                  size: 18,
                  color: Color(0xFF1877F2),
                ),
                SizedBox(width: AppSpacing.xs),
                Text('Facebook'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(ThemeData theme, AuthState state) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(
          'Already have an account?',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        TextButton(
          onPressed: state.isSubmitting ? null : widget.onSignIn,
          child: const Text('Log In'),
        ),
      ],
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

/// An independent show/hide control for one password field.
///
/// The label describes the action the tap performs, so a screen-reader user
/// hears "Show password" or "Hide password" rather than "eye".
class _PasswordVisibilityToggle extends StatelessWidget {
  const _PasswordVisibilityToggle({
    required this.visible,
    required this.onPressed,
  });

  /// Whether the password is currently visible.
  final bool visible;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(
        visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
      ),
      tooltip: visible ? 'Hide password' : 'Show password',
    );
  }
}
