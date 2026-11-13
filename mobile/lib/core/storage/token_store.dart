/// Narrow contract for storing and retrieving the Sanctum bearer token.
///
/// [ApiClient] depends on this rather than on the concrete
/// [TokenStorage] so the client can be unit-tested without spinning up
/// platform channels for the Android Keystore or the iOS Keychain.
///
/// Only one implementation exists today — `TokenStorage`. Do not add a
/// second backend for this. In particular, do not add an unencrypted
/// fallback: silently downgrading credential storage is a security
/// regression, not a convenience.
library;

abstract interface class TokenStore {
  /// Returns the stored bearer token, or `null` when signed out.
  Future<String?> read();

  /// Stores the bearer token, replacing any previous value.
  ///
  /// With [persist] false ("Remember me" unticked) the token is kept only for
  /// the life of the app process and any previously saved token is removed,
  /// so closing the app signs the user out. It is never written unencrypted.
  Future<void> write(String token, {bool persist = true});

  /// Removes the stored bearer token. Must be safe to call when nothing is
  /// stored.
  Future<void> clear();

  /// Removes [expectedToken] only if it is still the current token.
  ///
  /// A delayed response from an old session must not clear a token that was
  /// written for a newer account while that response was in flight.
  Future<bool> clearIfCurrent(String expectedToken);
}
