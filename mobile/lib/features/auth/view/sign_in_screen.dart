import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../widgets/field_label.dart';
import '../state/auth_scope.dart';
import '../state/auth_state.dart';
import '../widgets/auth_error_banner.dart';
import '../widgets/auth_notice_banner.dart';
import '../widgets/auth_scenic_header.dart';
import '../widgets/google_sign_in_button.dart';
import 'auth_validators.dart';

/// `POST /auth/login`, or `POST /auth/google`.
///
/// Email and password, or Google on Android. There is no role choice: this app
/// has one account per person.
///
/// The layout follows `AgroBenta_Login_DESIGN.md` — the branded landscape hero
/// overlapped by the white login card, mirroring the registration screen so the
/// two read as one experience. Notes on the reference's controls:
///
///  * **Remember me** — ticked by default. Ticked keeps the user signed in
///    after the app is closed; unticked ends the session when the app is
///    closed (project decision, MS-11, 2026-11-11). It applies to both email
///    and Google sign-in.
///  * **Social sign-in** — Google only; Facebook was removed (project decision,
///    MS-11, 2026-11-10). The Google button and its divider are hidden where
///    Google sign-in is unavailable (web, or no `GOOGLE_SERVER_CLIENT_ID`).
class SignInScreen extends StatefulWidget {
  const SignInScreen({
    required this.onRegister,
    required this.onForgotPassword,
    this.notice,
    super.key,
  });

  /// Switches to the registration form.
  final VoidCallback onRegister;
  final VoidCallback onForgotPassword;

  /// A confirmation to show above the form, such as after a password reset.
  final String? notice;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  /// Password visibility. Hidden by default, per the design.
  bool _obscurePassword = true;

  /// "Remember me". Ticked by default, so ignoring it keeps the user signed in.
  bool _rememberMe = true;

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

    final bool signedIn = await AuthScope.of(context).signIn(
      email: _email.text.trim(),
      password: _password.text,
      remember: _rememberMe,
    );

    if (!signedIn && mounted) {
      _password.clear();
    }
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
        // Just tall enough for the logo and tagline, so the brand sits close
        // to the form instead of floating above an empty band.
        (MediaQuery.sizeOf(context).height * 0.22 * textScale)
            .clamp(160.0, 240.0)
            .toDouble();

    // How far the white panel rides up over the hero's bottom edge.
    // The form panel sits directly under the white brand band.
    const double overlap = 0;

    return Scaffold(
      // White to the bottom edge, as in the approved design.
      backgroundColor: AppColors.surface,
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
      decoration: BoxDecoration(color: AppColors.surface),
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
                if (state.errorMessage != null) ...<Widget>[
                  AuthErrorBanner(message: state.errorMessage!),
                  const SizedBox(height: AppSpacing.lg),
                ] else if (widget.notice != null) ...<Widget>[
                  AuthNoticeBanner(message: widget.notice!),
                  const SizedBox(height: AppSpacing.lg),
                ],
                _buildFields(state),
                const SizedBox(height: AppSpacing.sm),
                _buildRememberForgotRow(theme, busy),
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
                      : const Text('Log In'),
                ),
                if (AuthScope.of(context).isGoogleSignInAvailable) ...<Widget>[
                  const SizedBox(height: AppSpacing.xl),
                  _buildDivider(theme),
                  const SizedBox(height: AppSpacing.lg),
                  GoogleSignInButton(
                    onPressed: busy
                        ? null
                        : () => AuthScope.of(
                            context,
                          ).signInWithGoogle(remember: _rememberMe),
                  ),
                ],
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
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const <String>[AutofillHints.email],
            autocorrect: false,
            decoration: const InputDecoration(
              label: FieldLabel('Email Address', hasPrefixIcon: true),
              prefixIcon: FieldIcon(Icon(Icons.mail_outline)),
            ),
            validator: (String? value) =>
                // A server 422 for this field outranks the local check: it is
                // the authority on, say, an address that is already registered.
                validateRequiredEmail(value) ?? state.errorFor('email'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _password,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            autofillHints: const <String>[AutofillHints.password],
            onFieldSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              label: FieldLabel('Password', hasPrefixIcon: true),
              prefixIcon: const FieldIcon(Icon(Icons.lock_outline)),
              suffixIcon: _PasswordVisibilityToggle(
                visible: !_obscurePassword,
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: validateRequiredPassword,
          ),
        ],
      ),
    );
  }

  Widget _buildRememberForgotRow(ThemeData theme, bool busy) {
    void toggle() => setState(() => _rememberMe = !_rememberMe);

    return Row(
      children: <Widget>[
        Expanded(
          child: InkWell(
            // The label toggles too, so the target is not just a 24 px box.
            onTap: busy ? null : toggle,
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: _rememberMe,
                    onChanged: busy ? null : (_) => toggle(),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    'Remember me',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        InkWell(
          onTap: widget.onForgotPassword,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Text(
              'Forgot Password?',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
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
          child: Text('or continue with', style: theme.textTheme.bodySmall),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }

  Widget _buildFooter(ThemeData theme, AuthState state) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(
          "Don't have an account?",
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        TextButton(
          onPressed: state.isSubmitting ? null : widget.onRegister,
          child: const Text('Sign Up'),
        ),
      ],
    );
  }
}

/// An independent show/hide control for the password field.
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
    return FieldIcon(
      IconButton(
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        icon: Icon(
          visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        ),
        tooltip: visible ? 'Hide password' : 'Show password',
      ),
    );
  }
}
