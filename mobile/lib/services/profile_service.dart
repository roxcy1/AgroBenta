import 'dart:io';
import 'package:http/http.dart' as http;

import '../core/constants/api_constants.dart';
import '../core/network/api_client.dart';
import '../models/user.dart';

class ProfileService {
  const ProfileService(this._client);

  final ApiClient _client;

  Future<User> show() {
    return _client.get<User>(
      ProfileEndpoints.show,
      parse: (Object? data) => User.fromJson(_asMap(data)),
    );
  }

  Future<User> update({
    String? name,
    String? email,
    String? phone,
    String? location,
    String? avatarUrl,
    String? bio,
    String? currentPassword,
  }) {
    final Map<String, dynamic> body = <String, dynamic>{
      'name': ?name,
      'email': ?email,
      'phone': ?phone,
      'location': ?location,
      'avatar_url': ?avatarUrl,
      'bio': ?bio,
      'current_password': ?currentPassword,
    };

    return _client.put<User>(
      ProfileEndpoints.update,
      body: body,
      parse: (Object? data) => User.fromJson(_asMap(data)),
    );
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    return _client.put<void>(
      ProfileEndpoints.changePassword,
      body: <String, dynamic>{
        'current_password': currentPassword,
        'password': newPassword,
        'password_confirmation': newPassword,
      },
      parse: (_) {},
    );
  }

  /// `POST /profile/avatar` — uploads a new avatar.
  ///
  /// Uses the shared `postMultipart` on [ApiClient] so the token, timeout,
  /// envelope unmarshaling and [ApiException] translation are all identical
  /// to a JSON request. Rolling a raw `http.MultipartRequest` here would
  /// duplicate that logic and drift.
  Future<User> uploadAvatar(File imageFile) async {
    final http.MultipartFile file = await http.MultipartFile.fromPath(
      'avatar',
      imageFile.path,
    );

    return _client.postMultipart<User>(
      path: ProfileEndpoints.uploadAvatar,
      files: <http.MultipartFile>[file],
      parse: (Object? data) => User.fromJson(_asMap(data)),
    );
  }

  static Map<String, dynamic> _asMap(Object? data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return data.cast<String, dynamic>();
    }
    throw const FormatException('Expected a JSON object for a user resource.');
  }
}