import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../state/profile_controller.dart';
import '../state/profile_scope.dart';
import '../state/profile_state.dart';

/// The change password form.
///
/// Three fields: current, new, confirm. The confirmation is validated on the
/// client so an obvious typo is caught before a round-trip; the server's
/// `confirmed` rule is what actually enforces it.
///
/// ## Error mapping
///
/// The server returns `422` for two different problems — a wrong current
/// password, or a new password that fails the policy — and Laravel's messages
/// under `errors.current_password` and `errors.password` are the clearest
/// wording available. Both are shown beside their field rather than rewritten,
/// and the form-level banner shows the top-level `message` so a `5xx` is not
/// swallowed.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  late final ProfileController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ProfileScope.readOf(context);
  }

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final bool changed = await _controller.changePassword(
      currentPassword: _current.text,
      newPassword: _next.text,
    );

    if (changed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password changed.')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change password')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (BuildContext context, Widget? child) {
            final ProfileState state = _controller.state;
            final bool isChanging =
                state.status == ProfileUiStatus.changingPassword;

            return ListView(
              padding: const EdgeInsets.all(AppSpacing.screenGutter),
              children: <Widget>[
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (state.errorMessage != null &&
                            state.fieldErrors.isEmpty) ...<Widget>[
                          _FormErrorBanner(message: state.errorMessage!),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        Form(
                          key: _formKey,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              TextFormField(
                                controller: _current,
                                obscureText: true,
                                enabled: !isChanging,
                                decoration: const InputDecoration(
                                  labelText: 'Current password',
                                ),
                                validator: (String? value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter your current password.';
                                  }
                                  return state.errorFor('current_password');
                                },
                              ),
                              const SizedBox(height: AppSpacing.md),
                              TextFormField(
                                controller: _next,
                                obscureText: true,
                                enabled: !isChanging,
                                decoration: const InputDecoration(
                                  labelText: 'New password',
                                  helperText: 'At least 8 characters.',
                                ),
                                validator: (String? value) {
                                  if (value == null || value.length < 8) {
                                    return 'Password must be at least 8 characters.';
                                  }
                                  return state.errorFor('password');
                                },
                              ),
                              const SizedBox(height: AppSpacing.md),
                              TextFormField(
                                controller: _confirm,
                                obscureText: true,
                                enabled: !isChanging,
                                decoration: const InputDecoration(
                                  labelText: 'Confirm new password',
                                ),
                                validator: (String? value) {
                                  if (value != _next.text) {
                                    return 'Passwords do not match.';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        FilledButton(
                          onPressed: isChanging ? null : _submit,
                          child: isChanging
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Change password'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FormErrorBanner extends StatelessWidget {
  const _FormErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: const Border(
          left: BorderSide(color: AppColors.error, width: 3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.error_outline, size: 20, color: AppColors.error),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: Text(message, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}