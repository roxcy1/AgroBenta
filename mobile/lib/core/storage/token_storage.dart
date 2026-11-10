import 'dart:async';

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
/// ## Remember me
///
/// `write(token, persist: false)` keeps the token in this object's memory
/// only and deletes any saved token, so it disappears when the app process
/// ends. Nothing is ever written outside the keystore.
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
  Future<void> _writeQueue = Future<void>.value();

  /// A "Remember me"-unticked token. Lives only as long as the app process.
  String? _sessionToken;

  @override
  Future<String?> read() async =>
      _sessionToken ?? await _storage.read(key: ApiConstants.tokenStorageKey);

  @override
  Future<void> write(String token, {bool persist = true}) =>
      _serialize<void>(() async {
        if (persist) {
          _sessionToken = null;
          await _storage.write(key: ApiConstants.tokenStorageKey, value: token);
        } else {
          // Remove any remembered token first, so a later launch cannot
          // restore an older session.
          await _storage.delete(key: ApiConstants.tokenStorageKey);
          _sessionToken = token;
        }
      });

  @override
  Future<void> clear() => _serialize<void>(() async {
    _sessionToken = null;
    await _storage.delete(key: ApiConstants.tokenStorageKey);
  });

  @override
  Future<bool> clearIfCurrent(String expectedToken) =>
      _serialize<bool>(() async {
        final String? current =
            _sessionToken ??
            await _storage.read(key: ApiConstants.tokenStorageKey);
        if (current != expectedToken) return false;
        _sessionToken = null;
        await _storage.delete(key: ApiConstants.tokenStorageKey);
        return true;
      });

  /// Serializes credential mutations so a compare-and-clear cannot race a
  /// token write for a newly authenticated account.
  Future<T> _serialize<T>(Future<T> Function() operation) {
    final Completer<T> result = Completer<T>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        result.complete(await operation());
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}
