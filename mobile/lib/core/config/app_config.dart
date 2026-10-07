import 'package:flutter/foundation.dart';

/// Centralised, build-time application configuration.
///
/// Nothing in this app may hard-code a URL. Every network-facing base URL is
/// resolved here so there is exactly one place to change per environment.
///
/// ## The Android host address rule
///
/// The Android emulator runs behind a virtual network bridge. `localhost` inside
/// the emulator is the emulator itself, **not** the development machine, so a
/// mobile app that works on the iOS simulator will fail on Android if it uses
/// `localhost`.
///
/// To reach a service running on the host machine:
///
/// | Where the app runs   | Host address to use            |
/// |----------------------|--------------------------------|
/// | Android emulator     | `10.0.2.2` (opt-in, see below) |
/// | Physical device      | Your machine's LAN IP          |
/// | iOS simulator        | `localhost` (or `127.0.0.1`)   |
/// | Web / desktop        | `localhost`                    |
///
/// The defaults are deliberately **physical-device-first**. A native Android
/// build resolves to [physicalAndroidApiBaseUrl] unless the build opts into
/// the emulator host alias with `--dart-define=ANDROID_RUN_TARGET=emulator`,
/// so a physical-device development build can never silently fall back to the
/// emulator-only `10.0.2.2` address. Web is resolved from [kIsWeb] rather
/// than from the browser's user agent — see the note on [apiBaseUrl] for why
/// that distinction matters.
///
/// ## Browser origins
///
/// On Flutter Web the app is served by Chrome and calls Laravel directly, so it
/// is subject to the same-origin policy like any other client. `cors.php` must
/// list the Flutter Web dev server's origin (`http://localhost:8080`, the
/// `flutter run -d chrome` default) alongside the Admin Web's. Without it the
/// browser refuses the response even though the request reached Laravel.
///
/// ## Selecting the Android build target
///
/// Physical-device development is the default: a plain `flutter run` or
/// `flutter build apk --debug` resolves to [physicalAndroidApiBaseUrl]. The
/// emulator host alias is **opt-in**:
///
/// ```sh
/// # Android emulator against the local Docker stack (explicit opt-in)
/// flutter run --dart-define=ANDROID_RUN_TARGET=emulator
/// ```
///
/// Any value other than `emulator` — or no value at all — is a physical-device
/// build, so `10.0.2.2` can never be picked silently.
///
/// ## Overriding per build
///
/// Pass `--dart-define=API_BASE_URL` rather than editing this file when a
/// build must point somewhere other than the built-in defaults:
///
/// ```sh
/// # Physical device on the same Wi-Fi network (this is already the default)
/// flutter run --dart-define=API_BASE_URL=http://192.168.1.8:8001/api
///
/// # Android emulator
/// flutter run --dart-define=ANDROID_RUN_TARGET=emulator \
///              --dart-define=API_BASE_URL=http://10.0.2.2:8001/api
///
/// # Staging
/// flutter run --dart-define=API_BASE_URL=https://api.staging.agrobenta.test/api
/// ```
///
/// `API_BASE_URL` is the single canonical name for the URL. Do not introduce a
/// second spelling for the same value.
abstract final class AppConfig {
  /// Build-time override, e.g. `--dart-define=API_BASE_URL=...`.
  static const String _apiBaseUrlOverride = String.fromEnvironment(
    'API_BASE_URL',
  );

  /// Build-time selector for a native Android run target.
  ///
  /// Only the value `emulator` opts into [androidEmulatorApiBaseUrl]; any
  /// other value — or an unset define — is a physical-device build and
  /// resolves to [physicalAndroidApiBaseUrl]. See [resolveApiBaseUrl].
  static const String _androidRunTarget = String.fromEnvironment(
    'ANDROID_RUN_TARGET',
  );

  /// Laravel is served by Nginx on port 8001 in the Docker stack (see the
  /// repository root `README.md`). The API is mounted under `/api`.
  static const String localApiBaseUrl = 'http://localhost:8001/api';

  /// Default for a **physical-device** Android development build: the
  /// development machine's LAN IP, which a phone on the same Wi-Fi network
  /// reaches directly.
  ///
  /// This is the Android default precisely because the emulator's `10.0.2.2`
  /// loopback alias does not exist on a real phone — a physical build that
  /// falls back to it fails every request. If this machine's LAN IP ever
  /// changes, update this constant. Staging and production are expressed with
  /// `--dart-define=API_BASE_URL`, never by editing this constant.
  /// CHANGE_THIS_DEV_LAN_IP: the development machine's address in
  /// `ipconfig`.
  static const String physicalAndroidApiBaseUrl = 'http://192.168.1.8:8001/api';

  /// `10.0.2.2` is the Android emulator's alias for the host machine's loopback
  /// interface. Selected **only** when the build opts in with
  /// `--dart-define=ANDROID_RUN_TARGET=emulator`; it is never an Android
  /// default. See the class documentation for the full address table.
  static const String androidEmulatorApiBaseUrl = 'http://10.0.2.2:8001/api';

  /// Resolved API root, without a trailing slash.
  ///
  /// Resolution order:
  ///   1. the `API_BASE_URL` dart-define, when supplied;
  ///   2. a native Android build — [physicalAndroidApiBaseUrl] by default, or
  ///      [androidEmulatorApiBaseUrl] when `ANDROID_RUN_TARGET` is `emulator`;
  ///   3. [localApiBaseUrl] everywhere else, which includes Flutter Web.
  static String get apiBaseUrl => resolveApiBaseUrl(
    isWeb: kIsWeb,
    platform: defaultTargetPlatform,
    override: _apiBaseUrlOverride,
    androidTarget: _androidRunTarget,
  );

  /// The base-URL decision itself, as a pure function.
  ///
  /// Kept separate from [apiBaseUrl] so the platform matrix can be tested
  /// directly. `kIsWeb` and `defaultTargetPlatform` are compile-time and
  /// ambient — a `flutter test` run on the Dart VM can never observe
  /// `kIsWeb == true` — so without this seam the one branch that decides where
  /// the browser looks would be the one branch left untested.
  ///
  /// [isWeb] is `kIsWeb` and [platform] is `defaultTargetPlatform` in
  /// production. Callers pass them explicitly rather than this method reading
  /// them itself, so a test can express "a web build reporting Android" without
  /// having to fake a browser.
  ///
  /// [androidTarget] is the raw `ANDROID_RUN_TARGET` dart-define (`''` when
  /// unset). It only matters for a native Android build without a URL override,
  /// where `emulator` selects [androidEmulatorApiBaseUrl] and everything else
  /// selects [physicalAndroidApiBaseUrl] — so a physical build can never fall
  /// back to `10.0.2.2`.
  static String resolveApiBaseUrl({
    required bool isWeb,
    required TargetPlatform platform,
    required String override,
    String androidTarget = '',
  }) {
    final String trimmedOverride = override.trim();
    final String resolved = trimmedOverride.isNotEmpty
        ? trimmedOverride
        : switch (platform) {
            // Guarded on `!isWeb` deliberately. On Flutter Web,
            // `defaultTargetPlatform` is inferred from the *browser's* user
            // agent rather than from the build target, so Chrome's device
            // toolbar set to a phone profile makes it report Android. Honouring
            // that would hand the browser `10.0.2.2` — an alias that only exists
            // inside an Android emulator — and every request would fail while
            // looking like an unreachable backend. `kIsWeb` is a compile-time
            // constant about the platform being built, so device emulation
            // cannot influence it.
            TargetPlatform.android when !isWeb => androidTarget == 'emulator'
                ? androidEmulatorApiBaseUrl
                : physicalAndroidApiBaseUrl,
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
                if (entry.value != null) entry.key: '${entry.value}',
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
