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
  Future<void> write(String token);

  /// Removes the stored bearer token. Must be safe to call when nothing is
  /// stored.
  Future<void> clear();
}
