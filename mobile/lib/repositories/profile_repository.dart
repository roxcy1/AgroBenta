import '../models/user.dart';
import '../services/profile_service.dart';

/// Orchestration for the caller's own profile.
///
/// Thin, like the other repositories in this app: the transport is behind
/// [ProfileService], so there is no lifetime or ordering policy to arbitrate
/// here. Every call is a plain pass-through, and the repository exists so the
/// controller depends on an abstraction the tests can fake without a network.
class ProfileRepository {
  const ProfileRepository(this._service);

  final ProfileService _service;

  /// Reads the caller's own profile.
  Future<User> show() => _service.show();

  /// Updates the caller's own profile, sending only the named fields.
  Future<User> update({
    String? name,
    String? email,
    String? phone,
    String? location,
    String? avatarUrl,
    String? bio,
  }) {
    return _service.update(
      name: name,
      email: email,
      phone: phone,
      location: location,
      avatarUrl: avatarUrl,
      bio: bio,
    );
  }

  /// Changes the caller's password.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    return _service.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }
}