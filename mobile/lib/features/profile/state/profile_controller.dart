import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../models/user.dart';
import '../../../repositories/profile_repository.dart';
import 'profile_state.dart';

/// Presentation logic for the caller's own profile.
///
/// The only thing that mutates [state]. Screens call these methods and listen.
///
/// ## One read, one save
///
/// [load] is idempotent while a read is in flight; [save] refuses a second
/// call while one is running, the same guard `SellerVerificationController`
/// uses. The disabled button stops a tap; the guard stops the request already
/// on its way from being followed by another.
///
/// ## Errors are not all the same
///
/// A `422` from a save is a *field* problem and its errors land in
/// [ProfileState.fieldErrors] so the form can show them beside the inputs. A
/// `422` from a password change also lands in [ProfileState.fieldErrors], but
/// the password screen maps `current_password` and `password` keys to the
/// fields it already has on screen.
///
/// ## Success is a one-shot
///
/// A successful save publishes [ProfileState.successMessage] and the screen
/// shows a snackbar and then calls [consumeSuccess] to clear it. Without that
/// clear, the snackbar would be shown again on the next rebuild.
class ProfileController extends ChangeNotifier {
  ProfileController(this._repository);

  final ProfileRepository _repository;

  ProfileState _state = const ProfileState();
  ProfileState get state => _state;

  bool _disposed = false;
  bool _loading = false;
  int _generation = 0;

  /// Reads the caller's own profile.
  ///
  /// A failure leaves the last successful [ProfileState.user] in place, so a
  /// screen that has already rendered a profile shows a stale one rather than
  /// blanking. That is the same rule `SellerVerificationController` applies to
  /// its record.
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

  /// Saves the given fields. Returns `true` when the server accepted the update.
  ///
  /// Only the fields the caller passes are sent; a `null` argument means
  /// "leave this field alone", and an empty string is a real value the user
  /// cleared. That is what makes a partial update a partial update.
  Future<bool> save({
    String? name,
    String? email,
    String? phone,
    String? location,
    String? avatarUrl,
    String? bio,
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
          // A 422 carries per-field messages; a form-level banner would be
          // redundant noise above them, so the top-level message is left empty
          // for that kind alone.
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

  /// Changes the caller's password. Returns `true` on success.
  ///
  /// A `422` here means the current password was wrong, or the new one failed
  /// the policy. The server's message is the clearest wording available, so it
  /// is shown as a form-level error rather than being rewritten.
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