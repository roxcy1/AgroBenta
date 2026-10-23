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

/// `POST /auth/login`.
///
/// Email and password only. There is no "forgot password", no "remember me" and
/// no social sign-in: this app has one account per person and one way in, so
/// there is no role choice here either.
///
/// The layout follows `AgroBenta_Login_DESIGN.md` — the branded landscape hero
/// overlapped by the white login card, mirroring the registration screen so the
/// two read as one experience. Three controls the reference shows are **not**
/// backed by the backend, and are handled honestly rather than faked:
///
///  * **Remember me** — a Sanctum token is always kept until logout, so there is
///    no "remembered" versus "session" distinction to switch. The checkbox is
///    rendered inert.
///  * **Forgot Password?** — there is no password-recovery endpoint, so the
///    label is styled but not navigable; no destination is invented.
///  * **Social sign-in** — the backend implements no Google/Facebook OAuth, so
///    the buttons are rendered disabled rather than implying a capability that
///    is not there.
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

  /// Password visibility. Hidden by default, per the design.
  bool _obscurePassword = true;

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
                  'Welcome Back!',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Sign in to continue',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (state.errorMessage != null) ...<Widget>[
                  AuthErrorBanner(message: state.errorMessage!),
                  const SizedBox(height: AppSpacing.lg),
                ],
                _buildFields(state),
                const SizedBox(height: AppSpacing.sm),
                _buildRememberForgotRow(theme),
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
                const SizedBox(height: AppSpacing.xl),
                _buildDivider(theme),
                const SizedBox(height: AppSpacing.lg),
                _buildSocialRow(),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Social sign-in is not available yet.',
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
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
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

  Widget _buildRememberForgotRow(ThemeData theme) {
    // Neither control is backed by the API: a token does not distinguish a
    // "remembered" session and there is no recovery endpoint. They are shown to
    // match the approved layout but are deliberately inert, so the screen never
    // implies a capability the backend does not have.
    return Row(
      children: <Widget>[
        Expanded(
          child: Row(
            children: <Widget>[
              const SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: false,
                  // Remember-me is not supported, so the control is inert.
                  onChanged: null,
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
        const SizedBox(width: AppSpacing.xs),
        // Styled as a link but deliberately not navigable: no approved
        // password-recovery destination exists, and inventing one is forbidden.
        Text(
          'Forgot Password?',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
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

  Widget _buildSocialRow() {
    // Disabled, not absent: the buttons are part of the approved layout, but the
    // backend implements no OAuth. A disabled control states the feature is not
    // available; a working-looking one would imply it is. The brand marks come
    // from Font Awesome — the project ships no Google/Facebook asset and
    // Material has no Google glyph — and keep their brand colours even while
    // disabled, because a greyed-out logo is no longer that logo.
    return Row(
      children: <Widget>[
        Expanded(
          child: OutlinedButton(
            onPressed: null,
            child: const FaIcon(
              FontAwesomeIcons.google,
              size: 26,
              color: Color(0xFF4285F4),
              semanticLabel: 'Continue with Google — unavailable',
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: OutlinedButton(
            onPressed: null,
            child: const FaIcon(
              FontAwesomeIcons.facebook,
              size: 26,
              color: Color(0xFF1877F2),
              semanticLabel: 'Continue with Facebook — unavailable',
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
    return IconButton(
      onPressed: onPressed,
      icon: Icon(
        visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
      ),
      tooltip: visible ? 'Hide password' : 'Show password',
    );
  }
}
