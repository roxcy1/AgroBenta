import '../core/constants/api_constants.dart';
import '../core/network/api_client.dart';
import '../models/user.dart';

/// The profile transport.
///
/// Thin on purpose: every request goes through [ApiClient], which owns the
/// bearer token, the envelope unwrapping and the `401` handling. The service's
/// only jobs are to know the paths and to shape the bodies from the allow-list
/// in [ProfileEndpoints.writableFields] so a screen cannot accidentally send a
/// server-owned field.
class ProfileService {
  const ProfileService(this._client);

  final ApiClient _client;

  /// `GET /profile` — the caller's own profile.
  Future<User> show() {
    return _client.get<User>(
      ProfileEndpoints.show,
      parse: (Object? data) => User.fromJson(_asMap(data)),
    );
  }

  /// `PUT /profile` — updates the fields that are not `null`.
  ///
  /// A `null` argument means "leave this field alone"; an empty string is a
  /// real value the user has cleared, and is sent. This is what makes the
  /// request a patch in effect: the caller names what changed.
  ///
  /// The `?` before a value is Dart's null-aware map entry: the entry is
  /// omitted entirely when the value is `null`, which is exactly the older
  /// `if (value != null)` behaviour in the form the SDK prefers now.
  Future<User> update({
    String? name,
    String? email,
    String? phone,
    String? location,
    String? avatarUrl,
    String? bio,
  }) {
    final Map<String, dynamic> body = <String, dynamic>{
      'name': ?name,
      'email': ?email,
      'phone': ?phone,
      'location': ?location,
      'avatar_url': ?avatarUrl,
      'bio': ?bio,
    };

    return _client.put<User>(
      ProfileEndpoints.update,
      body: body,
      parse: (Object? data) => User.fromJson(_asMap(data)),
    );
  }

  /// `PUT /profile/password` — changes the caller's password.
  ///
  /// Returns nothing: the server's response is message-only, and the value the
  /// screen needs is "did it succeed", which the absence of an exception
  /// already answers.
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