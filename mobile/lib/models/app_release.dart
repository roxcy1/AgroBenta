import '../core/utils/json_utils.dart';

/// The latest published Android build, as served by `GET /app-release`.
///
/// [versionCode] is the build number after the `+` in `pubspec.yaml`
/// (`1.0.1+2` → 2). It is what decides whether an update exists: Android itself
/// only installs a build whose code is higher than the installed one.
class AppRelease {
  const AppRelease({
    required this.versionName,
    required this.versionCode,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.sha256,
    required this.notes,
    required this.publishedAt,
  });

  factory AppRelease.fromJson(Map<String, dynamic> json) {
    return AppRelease(
      versionName: readString(json, 'version_name'),
      versionCode: readInt(json, 'version_code'),
      downloadUrl: readString(json, 'download_url'),
      sizeBytes: readInt(json, 'size_bytes'),
      sha256: readString(json, 'sha256'),
      notes: readNullableString(json, 'notes'),
      publishedAt: readDateTime(json, 'published_at'),
    );
  }

  final String versionName;
  final int versionCode;

  /// The absolute HTTPS URL of the APK.
  final String downloadUrl;
  final int sizeBytes;
  final String sha256;

  /// Optional "what's new" text.
  final String? notes;
  final DateTime publishedAt;
}
