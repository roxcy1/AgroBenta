import '../../../models/user.dart';

/// Where the app is in the authentication lifecycle.
enum AuthStatus {
  /// Deciding whether this device already has a usable session. The gate shows
  /// a loading state; it must never show the sign-in form here, or a returning
  /// user sees a flash of the wrong screen before being restored.
  restoring,

  /// A token is stored but could not be verified — typically the API is
  /// unreachable. Distinct from [signedOut]: the session may well still be
  /// valid, so this state offers a retry rather than a sign-in form.
  restoreFailed,

  /// No usable session. Show the sign-in or registration form.
  signedOut,

  /// A verified session with a current [User].
  signedIn,
}

/// An immutable snapshot of everything the auth UI renders from.
///
/// Screens read this and nothing else; they never ask the repository directly.
class AuthState {
  const AuthState({
    required this.status,
    this.user,
    this.isSubmitting = false,
    this.isSigningOut = false,
    this.errorMessage,
    this.validationErrors = const <String, List<String>>{},
  });

  /// The state the app starts in: a stored token, if any, has not been checked
  /// yet.
  const AuthState.initial() : this(status: AuthStatus.restoring);

  final AuthStatus status;

  /// The authenticated user, set only while [status] is [AuthStatus.signedIn].
  final User? user;

  /// A sign-in or registration request is in flight. The submit button is
  /// disabled while this is true so a tap cannot fire twice.
  final bool isSubmitting;

  /// A logout request is in flight.
  final bool isSigningOut;

  /// A user-facing failure for the current screen, or `null` when there is
  /// none. Always safe to display: it is either a server `message` or a
  /// sensible default chosen per error kind.
  final String? errorMessage;

  /// Laravel's per-field `422` messages, keyed by field name, for mapping onto
  /// the form.
  final Map<String, List<String>> validationErrors;

  /// Whether a session is currently established.
  bool get isSignedIn => status == AuthStatus.signedIn;

  /// Whether the first session check has finished, successfully or not.
  bool get isRestoring => status == AuthStatus.restoring;

  /// The first validation message for [field], or `null`.
  String? errorFor(String field) {
    final List<String>? messages = validationErrors[field];
    if (messages == null || messages.isEmpty) {
      return null;
    }
    return messages.first;
  }

  AuthState copyWith({
    AuthStatus? status,
    User? user,
    bool? isSubmitting,
    bool? isSigningOut,
    String? errorMessage,
    Map<String, List<String>>? validationErrors,
    bool clearError = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isSigningOut: isSigningOut ?? this.isSigningOut,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      validationErrors: validationErrors ?? this.validationErrors,
    );
  }

  @override
  String toString() =>
      'AuthState(${status.name}, submitting: $isSubmitting, '
      'signingOut: $isSigningOut)';
}
