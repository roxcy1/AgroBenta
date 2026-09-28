import '../core/constants/api_constants.dart';
import '../core/network/api_client.dart';
import '../models/auth_session.dart';
import '../models/user.dart';

/// The mobile authentication API surface.
///
/// One method per endpoint in this app's contract, and nothing else: no token
/// handling, no persistence, no error translation beyond what [ApiClient]
/// already does. Those belong to `AuthRepository`.
///
/// The bearer token is attached by [ApiClient] from `TokenStore`, so
/// [login] and [register] simply do not have one yet and [me] and [logout]
/// do.
class AuthService {
  const AuthService(this._apiClient);

  final ApiClient _apiClient;

  /// `POST /auth/register` — creates a buyer account and returns a session.
  ///
  /// [passwordConfirmation] is sent as `password_confirmation` because the
  /// backend validates `password` with Laravel's `confirmed` rule, which
  /// compares the two server-side.
  ///
  /// [deviceName] is optional and only included when supplied. The backend
  /// validates it but currently ignores it — `MobileAuthService` names every
  /// mobile token `mobile` — so the app does not invent one.
  ///
  /// Throws `ApiException` with `ApiErrorKind.validation` carrying per-field
  /// messages for a `422`, including a duplicate email.
  Future<AuthSession> register({
    required String name,
    required String email,
    required String password,
    required String passwordConfirmation,
    String? deviceName,
  }) {
    return _apiClient.post<AuthSession>(
      AuthEndpoints.register,
      // Explicit allow-list. `role` and `seller_capability` are server-owned
      // and must never be sent from a device — see mobile/AGENTS.md §B.
      body: <String, dynamic>{
        'name': name,
        'email': email,
        'password': password,
        'password_confirmation': passwordConfirmation,
        if (deviceName != null && deviceName.isNotEmpty)
          'device_name': deviceName,
      },
      parse: (Object? data) => AuthSession.fromJson(
        _asObject(data, 'register'),
      ),
    );
  }

  /// `POST /auth/login` — exchanges credentials for a session.
  ///
  /// A `401` means the email or password was wrong; the backend does not
  /// distinguish between the two, and neither does this app. A `403` means the
  /// account is an administrator, which may not use the mobile app.
  Future<AuthSession> login({
    required String email,
    required String password,
  }) {
    return _apiClient.post<AuthSession>(
      AuthEndpoints.login,
      body: <String, dynamic>{'email': email, 'password': password},
      parse: (Object? data) => AuthSession.fromJson(_asObject(data, 'login')),
    );
  }

  /// `GET /auth/me` — the authenticated user's own profile.
  ///
  /// Used on session restoration to prove a stored token is still valid and to
  /// load the current user. A `401` means the token was revoked, and
  /// `ApiClient` has already cleared it from storage by the time this throws.
  Future<User> me() {
    return _apiClient.get<User>(
      AuthEndpoints.me,
      parse: (Object? data) => User.fromJson(_asObject(data, 'me')),
    );
  }

  /// `POST /auth/logout` — revokes the caller's current mobile token.
  ///
  /// The response carries only a message, so there is nothing to return. Its
  /// shape is `{"success": true, "message": "..."}` with no `data` key, which
  /// `ApiClient` normalises to a null payload before parsing.
  Future<void> logout() {
    return _apiClient.post<void>(
      AuthEndpoints.logout,
      // The endpoint returns no payload; the empty body of this callback is the
      // result.
      parse: (Object? _) {},
    );
  }

  /// Casts an unwrapped `data` payload to a JSON object with a message that
  /// names the endpoint, instead of a bare cast error.
  ///
  /// A `FormatException` here is translated by `ApiClient` into
  /// `ApiErrorKind.malformedResponse`.
  static Map<String, dynamic> _asObject(Object? data, String context) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return data.cast<String, dynamic>();
    }
    throw FormatException(
      'Expected the $context response data to be a JSON object, got '
      '${data.runtimeType}.',
    );
  }
}
