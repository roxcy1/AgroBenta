import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/user.dart';
import '../../../widgets/field_label.dart';
import '../../../widgets/local_image_preview.dart';
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
/// ## Avatar upload
///
/// The avatar is chosen from the gallery or the camera and shown as a local
/// preview. Nothing is uploaded while the user is still editing: the pending
/// image is sent by [Save] only, so leaving the form with Back or Cancel
/// discards it with the rest of the unsaved changes. If the upload fails, the
/// preview is kept so the user can retry without picking the image again.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({this.imagePicker, super.key});

  /// The picker used for the avatar. Tests pass a fake; the app leaves it
  /// `null` so the real platform picker is used.
  final ImagePicker? imagePicker;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _bio;

  late final ProfileController _controller;
  late final User _initial;

  /// The image the user has just picked. Shown as a preview while the upload
  /// is in flight; cleared to null once the server confirms.
  XFile? _selectedImage;

  /// Whether the avatar upload is in flight. Disables the save button so a
  /// half-finished avatar cannot be committed.
  bool _uploadingAvatar = false;

  /// The current avatar as it appears on the form. Sourced from the profile,
  /// then overridden by a fresh upload.
  String? _currentAvatarUrl;

  late final ImagePicker _imagePicker;

  /// The field errors currently on screen, so a repeat of the same server error
  /// does not re-validate for nothing.
  Map<String, List<String>> _displayedErrors = const <String, List<String>>{};

  @override
  void initState() {
    super.initState();
    _imagePicker = widget.imagePicker ?? ImagePicker();
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
    _bio = TextEditingController(text: _initial.bio ?? '');
    _currentAvatarUrl = _initial.avatarUrl;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _bio.dispose();
    super.dispose();
  }

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

  /// A corrected value invalidates server errors from the previous attempt.
  ///
  /// Clearing the controller's errors also lets `FormState.validate()` apply
  /// the regular client-side rules again, so a 422 does not permanently block
  /// a retry with corrected input.
  void _clearServerErrorsWhenEdited() {
    final ProfileState state = _controller.state;
    if (state.errorMessage == null && state.fieldErrors.isEmpty) {
      return;
    }

    _controller.clearError();
  }

  /// Opens the image-source picker: gallery or camera.
  Future<void> _pickAvatarSource() async {
    if (_uploadingAvatar) {
      return;
    }

    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
            ],
          ),
        );
      },
    );

    if (source == null) {
      return;
    }

    final XFile? picked = await _imagePicker.pickImage(
      source: source,
      maxWidth: 800,
      imageQuality: 70,
    );
    if (picked == null || !mounted) {
      return;
    }

    // Selecting is local until Save. Uploading here would persist the change
    // even if the user then leaves the form without saving anything.
    setState(() => _selectedImage = picked);
  }

  /// Uploads the pending avatar, if the user picked one.
  ///
  /// Returns `true` when there is nothing to upload or the upload succeeded.
  /// On failure the preview is deliberately kept so [Save] can be retried
  /// without losing the user's choice.
  Future<bool> _uploadPendingAvatar() async {
    final XFile? pending = _selectedImage;
    if (pending == null) {
      return true;
    }
    if (!mounted) {
      return false;
    }

    setState(() => _uploadingAvatar = true);

    try {
      final User updated = await _controller.uploadAvatar(pending);
      if (!mounted) {
        return false;
      }
      setState(() {
        _currentAvatarUrl = updated.avatarUrl;
        _selectedImage = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile picture updated.')));
      return true;
    } on Object catch (error) {
      if (!mounted) {
        return false;
      }
      // A server rejection carries the clearest wording available (for example
      // a 422 naming the size or type restriction); anything else keeps the
      // generic retry copy.
      final String message = error is ApiException
          ? error.message
          : 'Could not upload the picture. Please try again.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return false;
    } finally {
      if (mounted) {
        setState(() => _uploadingAvatar = false);
      }
    }
  }

  Future<void> _save() async {
    if (_uploadingAvatar || _controller.state.isBusy) {
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final String name = _name.text.trim();
    final String email = _email.text.trim();
    final String phone = _phone.text.trim();
    final String bio = _bio.text.trim();

    final bool emailChanged = email != _initial.email;

    Future<bool> doSave({String? currentPassword}) {
      return _controller.save(
        name: name == _initial.name ? null : name,
        email: emailChanged ? email : null,
        phone: phone == (_initial.phone ?? '') ? null : phone,
        // The avatar is uploaded separately. Never send it as a text field.
        avatarUrl: null,
        bio: bio == (_initial.bio ?? '') ? null : bio,
        currentPassword: currentPassword,
      );
    }

    // Ask for the password before doing anything irreversible, so cancelling
    // the prompt leaves both the form and the server untouched.
    String? currentPassword;
    if (emailChanged) {
      currentPassword = await _promptCurrentPassword();
      if (currentPassword == null || currentPassword.isEmpty) {
        return;
      }
      if (!mounted) {
        return;
      }
    }

    // The avatar goes first so an upload failure aborts the whole save and
    // leaves every pending change on the form. A later field failure keeps the
    // avatar saved and the screen open, as before.
    if (!await _uploadPendingAvatar()) {
      return;
    }
    if (!mounted) {
      return;
    }

    while (true) {
      final bool saved = await doSave(currentPassword: currentPassword);
      if (saved && mounted) {
        Navigator.of(context).pop(true);
        return;
      }
      if (!mounted) {
        return;
      }

      if (!emailChanged) {
        return;
      }

      final String? error = _controller.state.errorFor('current_password');
      if (error == null) {
        return;
      }

      final String? nextPassword = await _promptCurrentPassword(error: error);
      if (nextPassword == null || nextPassword.isEmpty) {
        return;
      }
      currentPassword = nextPassword;
    }
  }

  Future<String?> _promptCurrentPassword({String? error}) async {
    final String? result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return _CurrentPasswordDialog(error: error);
      },
    );
    if (result == null || result.isEmpty) {
      return null;
    }
    return result;
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
            final bool isBusy = isSaving || _uploadingAvatar;

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
                              // Avatar picker, at the top of the form.
                              _AvatarPicker(
                                selectedImage: _selectedImage,
                                currentAvatarUrl: _currentAvatarUrl,
                                isUploading: _uploadingAvatar,
                                onTap: isBusy ? null : _pickAvatarSource,
                              ),
                              const SizedBox(height: AppSpacing.lg),

                              TextFormField(
                                controller: _name,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                maxLength: 120,
                                enabled: !isBusy,
                                onChanged: (_) =>
                                    _clearServerErrorsWhenEdited(),
                                decoration: const InputDecoration(
                                  label: FieldLabel('Full name'),
                                  helperText: 'Required.',
                                ),
                                validator: (String? value) {
                                  if (value == null ||
                                      value.trim().length < 2) {
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
                                enabled: !isBusy,
                                onChanged: (_) =>
                                    _clearServerErrorsWhenEdited(),
                                decoration: const InputDecoration(
                                  label: FieldLabel('Email address'),
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
                                enabled: !isBusy,
                                onChanged: (_) =>
                                    _clearServerErrorsWhenEdited(),
                                decoration: const InputDecoration(
                                  label: FieldLabel('Phone number'),
                                  helperText: 'Optional.',
                                ),
                                validator: (String? value) =>
                                    state.errorFor('phone'),
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
                                enabled: !isBusy,
                                onChanged: (_) =>
                                    _clearServerErrorsWhenEdited(),
                                decoration: const InputDecoration(
                                  label: FieldLabel('Bio'),
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
                          onPressed: isBusy ? null : _save,
                          child: isBusy
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

/// The avatar picker: circle preview, camera button, and optional spinner.
class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({
    required this.selectedImage,
    required this.currentAvatarUrl,
    required this.isUploading,
    required this.onTap,
  });

  final XFile? selectedImage;
  final String? currentAvatarUrl;
  final bool isUploading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool hasNetworkAvatar =
        currentAvatarUrl != null && currentAvatarUrl!.isNotEmpty;

    return Center(
      child: Stack(
        children: <Widget>[
          GestureDetector(
            onTap: onTap,
            // A locally picked file is previewed from its bytes, so the photo
            // step does not depend on `dart:io` and works on Flutter Web too.
            child: SizedBox.square(
              dimension: 112,
              child: selectedImage != null
                  ? ClipOval(
                      child: LocalImagePreview(
                        file: selectedImage!,
                        fallback: Container(
                          color: AppColors.background,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.person,
                            size: 56,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    )
                  : CircleAvatar(
                      radius: 56,
                      backgroundColor: AppColors.background,
                      backgroundImage: hasNetworkAvatar
                          ? NetworkImage(currentAvatarUrl!)
                          : null,
                      child: hasNetworkAvatar
                          ? null
                          : const Icon(
                              Icons.person,
                              size: 56,
                              color: AppColors.textSecondary,
                            ),
                    ),
            ),
          ),
          if (isUploading)
            const Positioned.fill(
              child: CircleAvatar(
                backgroundColor: Colors.black45,
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Material(
              color: AppColors.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.camera_alt, color: Colors.white, size: 18),
                ),
              ),
            ),
          ),
        ],
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
  const _CurrentPasswordDialog({this.error});

  final String? error;

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
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: _controller,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(
              label: const FieldLabel('Current password'),
              errorText: widget.error,
            ),
          ),
        ],
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
