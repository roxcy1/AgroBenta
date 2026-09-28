import '../core/utils/json_utils.dart';
import 'user.dart';

/// An authenticated session: the bearer token plus the user it belongs to.
///
/// This is the `data` payload of `POST /auth/register` (201) and
/// `POST /auth/login` (200), as built by
/// `backend/app/Http/Controllers/Api/Auth/AuthController.php`:
///
/// ```json
/// { "token": "1|abc...", "token_type": "Bearer", "user": { ...UserResource } }
/// ```
///
/// `GET /auth/me` returns the [User] on its own with no token, because the
/// token is already known — it came from secure storage.
class AuthSession {
  const AuthSession({
    required this.token,
    required this.tokenType,
    required this.user,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? user = readNullableObject(json, 'user');
    if (user == null) {
      throw FormatException(
        'Auth response is missing its "user" object.',
        json.toString(),
      );
    }

    return AuthSession(
      token: readString(json, 'token'),
      tokenType: readString(json, 'token_type'),
      user: User.fromJson(user),
    );
  }

  /// The Sanctum plain-text personal access token.
  ///
  /// This is a bearer credential: whoever holds it *is* the user. It is written
  /// only to `TokenStorage` (Android Keystore / iOS Keychain) and is never
  /// logged, printed, or displayed.
  final String token;

  /// Always `Bearer` today. Kept because the API sends it and Sanctum requires
  /// the prefix; the app does not switch on it.
  final String tokenType;

  final User user;

  @override
  String toString() => 'AuthSession($user, tokenType: $tokenType)';
}
