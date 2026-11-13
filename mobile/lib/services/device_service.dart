import '../core/constants/api_constants.dart';
import '../core/network/api_client.dart';

/// Push notification registration transport.
///
/// One call: hand the phone's FCM token to the backend for the signed-in
/// session. The body is built from the single allowed field.
class DeviceService {
  const DeviceService(this._client);

  final ApiClient _client;

  /// `POST /devices` — register [token] for the current session.
  Future<void> register(String token) {
    return _client.post<void>(
      DeviceEndpoints.register,
      body: <String, dynamic>{'token': token},
      parse: (_) {},
    );
  }
}
