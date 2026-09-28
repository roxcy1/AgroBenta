import '../core/network/api_exception.dart';
import '../core/storage/token_store.dart';
import '../models/auth_session.dart';
import '../models/user.dart';
import '../services/auth_service.dart';

/// Orchestrates authentication: calls [AuthService] and keeps [TokenStore] in
/// step with it.
///
/// This is the layer that knows a session exists. The service only knows the
/// endpoints; the token's lifetime is decided here and nowhere else, so there
/// is exactly one answer to "is this device signed in?".
class AuthRepository {
  const AuthRepository(this._service, this._tokenStore);

  final AuthService _service;
  final TokenStore _tokenStore;

  /// Registers a buyer account and stores the returned token.
  Future<User> register({
    required String name,
    required String email,
    required String password,
    required String passwordConfirmation,
    String? deviceName,
  }) async {
    final AuthSession session = await _service.register(
      name: name,
      email: email,
      password: password,
      passwordConfirmation: passwordConfirmation,
      deviceName: deviceName,
    );
    await _persist(session);
    return session.user;
  }

  /// Signs in and stores the returned token.
  Future<User> login({required String email, required String password}) async {
    final AuthSession session = await _service.login(
      email: email,
      password: password,
    );
    await _persist(session);
    return session.user;
  }

  /// Restores a session from the stored token, or returns `null` when the
  /// device is signed out.
  ///
  /// Three outcomes, and the difference matters:
  ///
  ///  * **no stored token** → `null`. Signed out, nothing to ask the server.
  ///  * **`401`** → `null`. The token was revoked. `ApiClient` has already
  ///    removed it from secure storage, so the app is genuinely signed out
  ///    and must not retry with it.
  ///  * **anything else** — a network failure, a `5xx`, a malformed body — is
  ///    rethrown. The token is still valid, and silently dropping the user
  ///    back to the sign-in screen because the API was briefly unreachable
  ///    would be wrong.
  Future<User?> restoreSession() async {
    final String? token = await _tokenStore.read();
    if (token == null || token.isEmpty) {
      return null;
    }

    try {
      return await _service.me();
    } on ApiException catch (error) {
      if (error.requiresReauthentication) {
        return null;
      }
      rethrow;
    }
  }

  /// Re-reads the signed-in user from `GET /auth/me`.
  ///
  /// For when the server has changed something the device already knows about —
  /// most importantly `seller_capability`, which moves to `seller` when an
  /// administrator approves a seller verification. Reading it is the only way
  /// this app can learn that; the capability is server-owned and is never
  /// written locally.
  ///
  /// The stored token is deliberately **not** rewritten: a refresh returns the
  /// user, not a new session, and re-persisting a token on every refresh would
  /// mean a keystore write for no reason.
  ///
  /// A `401` propagates, because `ApiClient` has already cleared the token and
  /// the device really is signed out; every other failure propagates too, with
  /// the session left intact.
  Future<User> refreshUser() => _service.me();

  /// Revokes the token server-side and clears it locally.
  ///
  /// A `401` here means the token was already revoked, so the device is signed
  /// out either way and this is not an error worth showing. Any other failure
  /// is rethrown with the token left in place, so the user can retry rather
  /// than being half-signed-out.
  Future<void> logout() async {
    try {
      await _service.logout();
    } on ApiException catch (error) {
      if (!error.requiresReauthentication) {
        rethrow;
      }
    }
    await _tokenStore.clear();
  }

  /// Clears the local token without contacting the server.
  ///
  /// For the case where the server has already invalidated the token, so there
  /// is nothing left to revoke.
  Future<void> forgetLocalSession() => _tokenStore.clear();

  /// Writes the token to secure storage.
  ///
  /// An empty token is treated as a contract violation rather than stored: a
  /// stored empty string would make `ApiClient` send no `Authorization` header
  /// at all, and the resulting `401` would be a confusing dead end.
  Future<void> _persist(AuthSession session) async {
    if (session.token.isEmpty) {
      throw const ApiException.malformedResponse(
        message: 'The server returned an empty authentication token.',
      );
    }
    await _tokenStore.write(session.token);
  }
}
