import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../models/user.dart';
import '../../../widgets/field_label.dart';
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
/// The avatar is chosen from the gallery or the camera and uploaded immediately
/// via `POST /profile/avatar`, rather than being typed in as a URL. This is
/// the "select from gallery" flow the task calls for; a URL field would
/// require users to host the image elsewhere first, which is not a viable
/// mobile flow.
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
  late final TextEditingController _bio;

  late final ProfileController _controller;
  late final User _initial;

  /// The image the user has just picked. Shown as a preview while the upload
  /// is in flight; cleared to null once the server confirms.
  File? _selectedImage;

  /// Whether the avatar upload is in flight. Disables the save button so a
  /// half-finished avatar cannot be committed.
  bool _uploadingAvatar = false;

  /// The current avatar as it appears on the form. Sourced from the profile,
  /// then overridden by a fresh upload.
  String? _currentAvatarUrl;

  final ImagePicker _imagePicker = ImagePicker();

  /// The field errors currently on screen, so a repeat of the same server error
  /// does not re-validate for nothing.
  Map<String, List<String>> _displayedErrors = const <String, List<String>>{};

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

    setState(() {
      _selectedImage = File(picked.path);
      _uploadingAvatar = true;
    });

    try {
      final User updated = await ProfileScope.readOf(
        context,
      ).uploadAvatar(File(picked.path));
      if (!mounted) {
        return;
      }
      setState(() {
        _currentAvatarUrl = updated.avatarUrl;
        _selectedImage = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile picture updated.')),
      );
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedImage = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not upload the picture. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _uploadingAvatar = false);
      }
    }
  }

  Future<void> _save() async {
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

    if (!emailChanged) {
      final bool saved = await doSave();
      if (saved && mounted) {
        Navigator.of(context).pop(true);
      }
      return;
    }

    String? currentPassword;
    while (true) {
      final String? password = await _promptCurrentPassword(
        error: currentPassword == null
            ? null
            : _controller.state.errorFor('current_password'),
      );
      if (password == null || password.isEmpty) {
        return;
      }
      currentPassword = password;
      final bool saved = await doSave(currentPassword: currentPassword);
      if (saved && mounted) {
        Navigator.of(context).pop(true);
        return;
      }
      if (!mounted) {
        return;
      }
      final String? error = _controller.state.errorFor('current_password');
      if (error == null) {
        return;
      }
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

/// The avatar picker: circle preview, camera button, and optional spinner.
class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({
    required this.selectedImage,
    required this.currentAvatarUrl,
    required this.isUploading,
    required this.onTap,
  });

  final File? selectedImage;
  final String? currentAvatarUrl;
  final bool isUploading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ImageProvider? imageProvider = selectedImage != null
        ? FileImage(selectedImage!)
        : (currentAvatarUrl != null && currentAvatarUrl!.isNotEmpty
              ? NetworkImage(currentAvatarUrl!)
              : null);

    return Center(
      child: Stack(
        children: <Widget>[
          GestureDetector(
            onTap: onTap,
            child: CircleAvatar(
              radius: 56,
              backgroundColor: AppColors.background,
              backgroundImage: imageProvider,
              child: imageProvider == null
                  ? const Icon(
                      Icons.person,
                      size: 56,
                      color: AppColors.textSecondary,
                    )
                  : null,
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
                  child: Icon(
                    Icons.camera_alt,
                    color: Colors.white,
                    size: 18,
                  ),
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