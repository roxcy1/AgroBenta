import 'package:flutter/foundation.dart';

import '../../../models/user.dart';

/// The screen states the profile feature can be in.
///
/// A closed enum rather than a set of booleans, so a screen cannot be both
/// `loading` and `saving` at once and every `switch` is exhaustive.
enum ProfileUiStatus {
  /// Nothing has been read yet.
  initial,

  /// The first read is in flight.
  loading,

  /// A profile is loaded and the screen may render it.
  ready,

  /// The first read failed. A retry is offered.
  failed,

  /// A save is in flight. The form is disabled.
  saving,

  /// A password change is in flight.
  changingPassword,
}

/// The immutable state of the profile feature.
@immutable
class ProfileState {
  const ProfileState({
    this.status = ProfileUiStatus.initial,
    this.user,
    this.errorMessage,
    this.fieldErrors = const <String, List<String>>{},
    this.successMessage,
  });

  final ProfileUiStatus status;

  /// The loaded profile, or the last one the server returned.
  final User? user;

  /// A form-level error, from a `4xx` or `5xx`.
  final String? errorMessage;

  /// Per-field validation errors, keyed by the field name the server sent.
  final Map<String, List<String>> fieldErrors;

  /// A one-shot success message for a snackbar — "Profile updated.", "Password
  /// changed." The screen clears it after showing it.
  final String? successMessage;

  /// Whether a request is in flight.
  bool get isBusy =>
      status == ProfileUiStatus.saving ||
      status == ProfileUiStatus.changingPassword;

  /// Whether the initial read is still running.
  bool get isLoading => status == ProfileUiStatus.loading;

  /// The first error for [field], or `null` if none.
  String? errorFor(String field) {
    final List<String>? messages = fieldErrors[field];
    return (messages == null || messages.isEmpty) ? null : messages.first;
  }

  /// Returns a copy with the given fields replaced.
  ///
  /// [clearError] and [clearSuccess] exist because a named nullable argument
  /// cannot distinguish "leave alone" from "set to null". A caller that wants
  /// to clear an error must say so explicitly, and every other caller gets the
  /// merge behaviour they expect.
  ProfileState copyWith({
    ProfileUiStatus? status,
    User? user,
    String? errorMessage,
    Map<String, List<String>>? fieldErrors,
    String? successMessage,
    bool clearError = false,
    bool clearSuccess = false,
  }) {
    return ProfileState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      fieldErrors: fieldErrors ?? this.fieldErrors,
      successMessage: clearSuccess
          ? null
          : (successMessage ?? this.successMessage),
    );
  }
}