import 'dart:convert';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/core/platform/installed_app.dart';
import 'package:agrobenta_mobile/features/app_update/state/app_update_scope.dart';
import 'package:agrobenta_mobile/repositories/app_release_repository.dart';
import 'package:agrobenta_mobile/services/app_release_service.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'auth_fakes.dart';

/// The installed app's version, without the `package_info_plus` channel.
class FakeInstalledApp implements InstalledApp {
  FakeInstalledApp({this.name = '1.0.0', this.code = 1});

  String name;
  int code;

  @override
  Future<InstalledVersion> version() async =>
      InstalledVersion(name: name, code: code);
}

/// Records the links the app would open in the browser.
class FakeLinkOpener implements ExternalLinkOpener {
  FakeLinkOpener({this.result = true});

  final bool result;
  final List<Uri> opened = <Uri>[];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return result;
  }
}

/// A `GET /app-release` body for [versionCode], or `data: null`.
Map<String, dynamic> appReleaseEnvelope({
  int? versionCode,
  String versionName = '1.0.1',
  String? notes,
  String downloadUrl =
      'https://agrobenta.example/storage/releases/agrobenta.apk',
}) {
  return successEnvelope(
    data: versionCode == null
        ? null
        : <String, dynamic>{
            'version_name': versionName,
            'version_code': versionCode,
            'download_url': downloadUrl,
            'size_bytes': 52428800,
            'sha256': 'abc123',
            'notes': notes,
            'published_at': '2026-11-14T00:00:00+00:00',
          },
  );
}

/// An [AppReleaseRepository] whose server answers with [envelope].
AppReleaseRepository fakeAppReleaseRepository({
  Map<String, dynamic>? envelope,
  InstalledApp? installedApp,
  ExternalLinkOpener? linkOpener,
  int statusCode = 200,
}) {
  return AppReleaseRepository(
    AppReleaseService(
      ApiClient(
        tokenStorage: FakeTokenStore(),
        httpClient: MockClient(
          (http.Request request) async => http.Response(
            jsonEncode(envelope ?? appReleaseEnvelope()),
            statusCode,
            headers: <String, String>{'content-type': 'application/json'},
          ),
        ),
      ),
    ),
    installedApp ?? FakeInstalledApp(),
    linkOpener ?? FakeLinkOpener(),
  );
}

/// The [AppUpdateScope] `main.dart` installs, answered with "no release".
class NoReleaseAppUpdateScope extends StatelessWidget {
  const NoReleaseAppUpdateScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppUpdateScope(
      repository: fakeAppReleaseRepository(envelope: appReleaseEnvelope()),
      child: child,
    );
  }
}
