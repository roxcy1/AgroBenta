import 'package:flutter/foundation.dart';

/// Centralised, build-time application configuration.
///
/// Nothing in this app may hard-code a URL. Every network-facing base URL is
/// resolved here so there is exactly one place to change per environment.
///
/// ## The Android emulator rule
///
/// The Android emulator runs behind a virtual network bridge. `localhost` inside
/// the emulator is the emulator itself, **not** the development machine, so a
/// mobile app that works on the iOS simulator will fail on Android if it uses
/// `localhost`.
///
/// To reach a service running on the host machine:
///
/// | Where the app runs   | Host address to use          |
/// |----------------------|------------------------------|
/// | Android emulator     | `10.0.2.2`                   |
/// | iOS simulator        | `localhost` (or `127.0.0.1`) |
/// | Physical device      | Your machine's LAN IP        |
/// | Web / desktop        | `localhost`                  |
///
/// The platform-aware defaults in [apiBaseUrl] already encode the first two
/// rows.
///
/// ## Overriding per build
///
/// Pass `--dart-define` rather than editing this file:
///
/// ```sh
/// # Android emulator against the local Docker stack (this is the default)
/// flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8001/api
///
/// # Physical device on the same Wi-Fi network
/// flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8001/api
///
/// # Staging
/// flutter run --dart-define=API_BASE_URL=https://api.staging.agrobenta.test/api
/// ```
///
/// `API_BASE_URL` is the single canonical name. Do not introduce a second
/// spelling for the same value.
abstract final class AppConfig {
  /// Build-time override, e.g. `--dart-define=API_BASE_URL=...`.
  static const String _apiBaseUrlOverride = String.fromEnvironment(
    'API_BASE_URL',
  );

  /// Laravel is served by Nginx on port 8001 in the Docker stack (see the
  /// repository root `README.md`). The API is mounted under `/api`.
  static const String localApiBaseUrl = 'http://localhost:8001/api';

  /// `10.0.2.2` is the Android emulator's alias for the host machine's loopback
  /// interface. See the class documentation for the full address table.
  static const String androidEmulatorApiBaseUrl = 'http://10.0.2.2:8001/api';

  /// Resolved API root, without a trailing slash.
  ///
  /// Resolution order:
  ///   1. the `API_BASE_URL` dart-define, when supplied;
  ///   2. [androidEmulatorApiBaseUrl] on Android;
  ///   3. [localApiBaseUrl] everywhere else.
  static String get apiBaseUrl {
    final String override = _apiBaseUrlOverride.trim();
    final String resolved = override.isNotEmpty
        ? override
        : switch (defaultTargetPlatform) {
            TargetPlatform.android => androidEmulatorApiBaseUrl,
            _ => localApiBaseUrl,
          };

    return _stripTrailingSlash(resolved);
  }

  /// Builds an absolute URL for an API [path].
  ///
  /// [path] is relative to the API root and must start with `/` — for example
  /// `/admin/dashboard`. Query parameters belong in the caller's `query` map,
  /// not in the path string.
  static String resolve(String path, {Map<String, dynamic>? query}) {
    final String normalisedPath = path.startsWith('/') ? path : '/$path';
    final Uri base = Uri.parse(apiBaseUrl);
    final Uri resolved = base.replace(
      path: '${base.path}$normalisedPath',
      queryParameters: (query == null || query.isEmpty)
          ? null
          : <String, String>{
              for (final MapEntry<String, dynamic> entry in query.entries)
                if (entry.value != null)
                  entry.key: '${entry.value}',
            },
    );

    return resolved.toString();
  }

  /// True when the app is talking to a plain-HTTP host.
  ///
  /// Android blocks cleartext traffic by default from API 28.
  /// `android/app/src/main/res/xml/network_security_config.xml` denies
  /// cleartext by default and re-permits it for `10.0.2.2`, `localhost` and
  /// `127.0.0.1` only, so the local Docker stack works while any other
  /// cleartext host is refused.
  ///
  /// This is a signal for environment setup, not something to branch on in
  /// feature code. If it is `true` and the host is not one of those three, the
  /// request will fail — fix the URL rather than working around it.
  static bool get isUsingCleartextHttp =>
      Uri.parse(apiBaseUrl).scheme == 'http';

  static String _stripTrailingSlash(String value) {
    var result = value;
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
