import '../core/constants/api_constants.dart';
import '../core/network/api_client.dart';
import '../models/app_release.dart';

/// App release transport: one public read.
class AppReleaseService {
  const AppReleaseService(this._client);

  final ApiClient _client;

  /// `GET /app-release` — the latest published build, or null before one is
  /// published.
  Future<AppRelease?> latest() {
    return _client.get<AppRelease?>(
      AppReleaseEndpoints.latest,
      parse: (Object? data) {
        if (data == null) {
          return null;
        }
        if (data is Map) {
          return AppRelease.fromJson(data.cast<String, dynamic>());
        }
        throw FormatException(
          'Expected the app release data to be a JSON object or null, got '
          '${data.runtimeType}.',
        );
      },
    );
  }
}
