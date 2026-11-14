import 'dart:io';

import '../models/user.dart';
import '../services/profile_service.dart';

/// Orchestration for the caller's own profile.
class ProfileRepository {
  const ProfileRepository(this._service);

  final ProfileService _service;

  Future<User> show() => _service.show();

  Future<User> update({
    String? name,
    String? email,
    String? phone,
    String? location,
    String? avatarUrl,
    String? bio,
    String? currentPassword,
  }) {
    return _service.update(
      name: name,
      email: email,
      phone: phone,
      location: location,
      avatarUrl: avatarUrl,
      bio: bio,
      currentPassword: currentPassword,
    );
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    return _service.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }

  /// Uploads a new avatar image.
  Future<User> uploadAvatar(File imageFile) => _service.uploadAvatar(imageFile);
}