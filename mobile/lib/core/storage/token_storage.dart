import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/api_constants.dart';
import 'token_store.dart';

/// [TokenStore] backed by the platform keystore.
///
/// ## Why not `shared_preferences`
///
/// `shared_preferences` on Android is an unencrypted XML file in app-private
/// storage. It is adequate for a preference, not for a credential. Sanctum
/// personal access tokens are bearer tokens: whoever holds one *is* the user.
/// This app uses the Android Keystore and the iOS Keychain via
/// `flutter_secure_storage`.
///
/// The Admin Web stores its token in `localStorage`, which is also
/// XSS-readable. That is an accepted risk for a browser tab on `localhost`; it
/// is not acceptable for a native app holding a long-lived token on a
/// user-supplied device.
///
/// In `flutter_secure_storage` v11 the Android `encryptedSharedPreferences`
/// flag no longer exists: Keystore-backed AES-GCM encryption is unconditional,
/// so [AndroidOptions.defaultOptions] is already the secure path. The iOS
/// options keep the token unreadable until the device has been unlocked once,
/// and stop it migrating to a new device via backup.
///
/// ## Not yet implemented
///
/// The backend issues Sanctum tokens with no expiry and there is no refresh
/// flow. Token lifetime policy is an open decision — see the API GAP register
/// in `mobile/AGENTS.md`. This class stores and retrieves a token; it does not
/// yet decide when one is stale.
class TokenStorage implements TokenStore {
  TokenStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions.defaultOptions,
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: ApiConstants.tokenStorageKey);

  @override
  Future<void> write(String token) =>
      _storage.write(key: ApiConstants.tokenStorageKey, value: token);

  @override
  Future<void> clear() => _storage.delete(key: ApiConstants.tokenStorageKey);
}
