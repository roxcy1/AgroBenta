import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the display-mode preference separately for each authenticated user.
abstract interface class AccountModePreferenceStore {
  Future<String?> read(int userId);

  Future<void> write(int userId, String mode);
}

/// Secure-storage implementation using the existing Flutter secure-storage
/// dependency. Account IDs namespace the preference so one user never inherits
/// another user's selected mode on this device.
class SecureAccountModePreferenceStore implements AccountModePreferenceStore {
  SecureAccountModePreferenceStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static String _key(int userId) => 'agrobenta.account_mode.user.$userId';

  @override
  Future<String?> read(int userId) => _storage.read(key: _key(userId));

  @override
  Future<void> write(int userId, String mode) =>
      _storage.write(key: _key(userId), value: mode);
}
