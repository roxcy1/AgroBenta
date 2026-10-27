import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/user.dart';
import '../state/profile_controller.dart';
import '../state/profile_scope.dart';
import '../state/profile_state.dart';

/// The profile edit form.
///
/// Every field starts from the current profile, and only the fields the user
/// changed are sent — the controller's `save` sends only the arguments it is
/// given, and the service only puts the non-`null` ones in the body.
///
/// `name` and `email` are the two the server treats as required; the rest are
/// optional and may be cleared.
///
/// ## Why the "only send what changed" comparison
///
/// The name is compared against the loaded value and, when it matches, `null`
/// is sent. That is not a micro-optimisation: `UpdateProfileRequest` validates
/// `email` with a `unique` rule `ignore`-ing the caller's own id, so a client
/// that resent the unchanged email would be fine — but a client that resends a
/// changed email while an unrelated field is being saved is a request the user
/// did not make. Sending only the diff keeps the request honest.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _location;
  late final TextEditingController _avatarUrl;
  late final TextEditingController _bio;

  late final ProfileController _controller;
  late final User _initial;

  /// The field errors currently on screen, so a repeat of the same server error
  /// does not re-validate for nothing.
  Map<String, List<String>> _displayedErrors = const <String, List<String>>{};



  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _location.dispose();
    _avatarUrl.dispose();
    _bio.dispose();
    super.dispose();
  }

  /// A `TextFormField` runs its validator when its value changes and when
  /// `validate()` is called — not when the widget rebuilds. A `422` therefore
  /// arrives after the last validation and would never appear on the field
  /// without this.
  ///
  /// Called from the [ListenableBuilder] rather than from
  /// `didChangeDependencies` because a `422` arrives as a controller
  /// notification, and this screen deliberately does **not** depend on the
  /// scope: it listens to the controller instead.
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

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final String name = _name.text.trim();
    final String email = _email.text.trim();
    final String phone = _phone.text.trim();
    final String location = _location.text.trim();
    final String avatarUrl = _avatarUrl.text.trim();
    final String bio = _bio.text.trim();

    final bool emailChanged = email != _initial.email;
    String? currentPassword;

    if (emailChanged) {
      final String? password = await _promptCurrentPassword();
      if (password == null || password.isEmpty) {
        return;
      }
      currentPassword = password;
    }

    final bool saved = await _controller.save(
      name: name == _initial.name ? null : name,
      email: emailChanged ? email : null,
      phone: phone == (_initial.phone ?? '') ? null : phone,
      location: location == (_initial.location ?? '') ? null : location,
      avatarUrl: avatarUrl == (_initial.avatarUrl ?? '') ? null : avatarUrl,
      bio: bio == (_initial.bio ?? '') ? null : bio,
      currentPassword: currentPassword,
    );

    if (saved && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<String?> _promptCurrentPassword() async {
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return const _CurrentPasswordDialog();
      },
    );
    if (result == null || result.isEmpty) {
      return null;
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    // `readOf`, not `of`: a dependency cannot be registered from `initState`.
    _controller = ProfileScope.readOf(context);
    _initial =
        _controller.state.user ??
        (throw StateError(
          'EditProfileScreen opened without a loaded profile.',
        ));

    _name = TextEditingController(text: _initial.name);
    _email = TextEditingController(text: _initial.email);
    _phone = TextEditingController(text: _initial.phone ?? '');
    _location = TextEditingController(text: _initial.location ?? '');
    _avatarUrl = TextEditingController(text: _initial.avatarUrl ?? '');
    _bio = TextEditingController(text: _initial.bio ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (BuildContext context, Widget? child) {
            final ProfileState state = _controller.state;
            final bool isSaving = state.status == ProfileUiStatus.saving;

            _revealServerFieldErrors(state.fieldErrors);

            return ListView(
              padding: const EdgeInsets.all(AppSpacing.screenGutter),
              children: <Widget>[
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (state.errorMessage != null) ...<Widget>[
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
                                controller: _name,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                maxLength: 120,
                                enabled: !isSaving,
                                decoration: const InputDecoration(
                                  labelText: 'Full name',
                                  helperText: 'Required.',
                                ),
                                validator: (String? value) {
                                  if (value == null || value.trim().length < 2) {
                                    return 'Please enter your name.';
                                  }
                                  return state.errorFor('name');
                                },
                              ),
                              const SizedBox(height: AppSpacing.md),
                              TextFormField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                maxLength: 191,
                                enabled: !isSaving,
                                decoration: const InputDecoration(
                                  labelText: 'Email address',
                                  helperText: 'Required.',
                                ),
                                validator: (String? value) {
                                  final String text = value?.trim() ?? '';
                                  if (text.isEmpty || !text.contains('@')) {
                                    return 'Please enter a valid email.';
                                  }
                                  return state.errorFor('email');
                                },
                              ),

                              const SizedBox(height: AppSpacing.md),
                              TextFormField(
                                controller: _phone,
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.next,
                                maxLength: 32,
                                enabled: !isSaving,
                                decoration: const InputDecoration(
                                  labelText: 'Phone number',
                                  helperText: 'Optional.',
                                ),
                                validator: (String? value) =>
                                    state.errorFor('phone'),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              TextFormField(
                                controller: _location,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                maxLength: 191,
                                enabled: !isSaving,
                                decoration: const InputDecoration(
                                  labelText: 'Location',
                                  helperText:
                                      'Optional. Town, city or province.',
                                ),
                                validator: (String? value) =>
                                    state.errorFor('location'),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              TextFormField(
                                controller: _avatarUrl,
                                keyboardType: TextInputType.url,
                                textInputAction: TextInputAction.next,
                                maxLength: 2048,
                                enabled: !isSaving,
                                decoration: const InputDecoration(
                                  labelText: 'Avatar URL',
                                  helperText:
                                      'Optional. A link to an image of you or '
                                      'your farm.',
                                ),
                                validator: (String? value) =>
                                    state.errorFor('avatar_url'),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              TextFormField(
                                controller: _bio,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                keyboardType: TextInputType.multiline,
                                minLines: 3,
                                maxLines: 6,
                                maxLength: 1000,
                                enabled: !isSaving,
                                decoration: const InputDecoration(
                                  labelText: 'Bio',
                                  alignLabelWithHint: true,
                                  helperText:
                                      'Optional. A short description of your '
                                      'farm or trading activity.',
                                ),
                                validator: (String? value) =>
                                    state.errorFor('bio'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        FilledButton(
                          onPressed: isSaving ? null : _save,
                          child: isSaving
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Save changes'),
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

/// A form-level failure, e.g. a `5xx` from the save.
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


class _CurrentPasswordDialog extends StatefulWidget {
  const _CurrentPasswordDialog();

  @override
  State<_CurrentPasswordDialog> createState() => _CurrentPasswordDialogState();
}

class _CurrentPasswordDialogState extends State<_CurrentPasswordDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm your password'),
      content: TextField(
        controller: _controller,
        obscureText: true,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Current password',
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
