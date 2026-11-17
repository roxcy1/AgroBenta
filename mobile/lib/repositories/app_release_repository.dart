import '../core/platform/installed_app.dart';
import '../models/app_release.dart';
import '../services/app_release_service.dart';

/// The result of comparing the installed app with the latest published build.
class AppUpdateCheck {
  const AppUpdateCheck({required this.installed, required this.latest});

  final InstalledVersion installed;

  /// Null when no release has been published yet.
  final AppRelease? latest;

  /// True only when the server's build number is higher than this app's, the
  /// same rule Android applies before it installs an update.
  bool get updateAvailable {
    final AppRelease? release = latest;
    return release != null && release.versionCode > installed.code;
  }
}

/// App update orchestration over [AppReleaseService], the installed app's
/// version, and the browser that downloads the APK.
class AppReleaseRepository {
  const AppReleaseRepository(
    this._service,
    this._installedApp,
    this._linkOpener,
  );

  final AppReleaseService _service;
  final InstalledApp _installedApp;
  final ExternalLinkOpener _linkOpener;

  Future<InstalledVersion> installedVersion() => _installedApp.version();

  Future<AppUpdateCheck> check() async {
    final InstalledVersion installed = await _installedApp.version();
    final AppRelease? latest = await _service.latest();
    return AppUpdateCheck(installed: installed, latest: latest);
  }

  /// Opens the APK download in the phone's browser; Android's installer takes
  /// it from there. Only HTTPS links from the server are opened.
  Future<bool> openDownload(AppRelease release) {
    final Uri? uri = Uri.tryParse(release.downloadUrl);
    if (uri == null || uri.scheme != 'https') {
      return Future<bool>.value(false);
    }
    return _linkOpener.open(uri);
  }
}
