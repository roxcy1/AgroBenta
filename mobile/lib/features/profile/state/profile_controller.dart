import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../models/user.dart';
import '../../../repositories/profile_repository.dart';
import 'profile_state.dart';

/// Presentation logic for the caller's own profile.
///
/// The only thing that mutates [state]. Screens call these methods and listen.
class ProfileController extends ChangeNotifier {
  ProfileController(this._repository);

  final ProfileRepository _repository;

  ProfileState _state = const ProfileState();
  ProfileState get state => _state;

  bool _disposed = false;
  bool _loading = false;
  int _generation = 0;

  /// Reads the caller's own profile.
  Future<void> load() async {
    if (_loading) {
      return;
    }
    _loading = true;

    final int generation = ++_generation;
    _set(
      _state.copyWith(
        status: ProfileUiStatus.loading,
        clearError: true,
        fieldErrors: const <String, List<String>>{},
      ),
    );

    try {
      final User user = await _repository.show();
      if (_disposed || generation != _generation) {
        return;
      }
      _set(
        _state.copyWith(
          status: ProfileUiStatus.ready,
          user: user,
          clearError: true,
        ),
      );
    } on ApiException catch (error) {
      if (_disposed || generation != _generation) {
        return;
      }
      _set(
        _state.copyWith(
          status: ProfileUiStatus.failed,
          errorMessage: error.message,
        ),
      );
    } on Object {
      if (_disposed || generation != _generation) {
        return;
      }
      _set(
        _state.copyWith(
          status: ProfileUiStatus.failed,
          errorMessage: 'Something went wrong. Please try again.',
        ),
      );
    } finally {
      _loading = false;
    }
  }

  /// Re-fetches the profile while keeping what is on screen.
  Future<void> refresh() => load();

  /// Saves the given fields. Returns `true` when the server accepted the update.
  Future<bool> save({
    String? name,
    String? email,
    String? phone,
    String? location,
    String? avatarUrl,
    String? bio,
    String? currentPassword,
  }) async {
    if (_state.isBusy) {
      return false;
    }

    _set(
      _state.copyWith(
        status: ProfileUiStatus.saving,
        clearError: true,
        clearSuccess: true,
        fieldErrors: const <String, List<String>>{},
      ),
    );

    try {
      final User updated = await _repository.update(
        name: name,
        email: email,
        phone: phone,
        location: location,
        avatarUrl: avatarUrl,
        bio: bio,
        currentPassword: currentPassword,
      );

      if (_disposed) {
        return false;
      }

      _set(
        _state.copyWith(
          status: ProfileUiStatus.ready,
          user: updated,
          successMessage: 'Profile updated.',
        ),
      );
      return true;
    } on ApiException catch (error) {
      if (_disposed) {
        return false;
      }
      _set(
        _state.copyWith(
          status: ProfileUiStatus.ready,
          errorMessage: error.kind == ApiErrorKind.validation
              ? null
              : error.message,
          fieldErrors: error.validationErrors,
        ),
      );
      return false;
    } on Object {
      if (_disposed) {
        return false;
      }
      _set(
        _state.copyWith(
          status: ProfileUiStatus.ready,
          errorMessage: 'Something went wrong. Please try again.',
        ),
      );
      return false;
    }
  }

  /// Uploads a new avatar and merges the server's response into [state].
  Future<User> uploadAvatar(File imageFile) async {
    final User updated = await _repository.uploadAvatar(imageFile);
    _set(_state.copyWith(user: updated));
    return updated;
  }

  /// Changes the caller's password. Returns `true` on success.
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (_state.isBusy) {
      return false;
    }

    _set(
      _state.copyWith(
        status: ProfileUiStatus.changingPassword,
        clearError: true,
        clearSuccess: true,
        fieldErrors: const <String, List<String>>{},
      ),
    );

    try {
      await _repository.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );

      if (_disposed) {
        return false;
      }

      _set(
        _state.copyWith(
          status: ProfileUiStatus.ready,
          successMessage: 'Password changed.',
        ),
      );
      return true;
    } on ApiException catch (error) {
      if (_disposed) {
        return false;
      }
      _set(
        _state.copyWith(
          status: ProfileUiStatus.ready,
          errorMessage: error.message,
          fieldErrors: error.validationErrors,
        ),
      );
      return false;
    } on Object {
      if (_disposed) {
        return false;
      }
      _set(
        _state.copyWith(
          status: ProfileUiStatus.ready,
          errorMessage: 'Something went wrong. Please try again.',
        ),
      );
      return false;
    }
  }

  /// Clears a shown success message so it is not shown twice.
  void consumeSuccess() {
    if (_state.successMessage == null) {
      return;
    }
    _set(_state.copyWith(clearSuccess: true));
  }

  /// Clears a form-level error so a retry starts clean.
  void clearError() {
    if (_state.errorMessage == null && _state.fieldErrors.isEmpty) {
      return;
    }
    _set(
      _state.copyWith(
        clearError: true,
        fieldErrors: const <String, List<String>>{},
      ),
    );
  }

  void _set(ProfileState next) {
    if (_disposed) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}