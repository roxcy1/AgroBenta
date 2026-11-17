import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// The version of this installed app, from `pubspec.yaml`'s `version:`
/// (`1.0.1+2` → name `1.0.1`, code 2).
class InstalledVersion {
  const InstalledVersion({required this.name, required this.code});

  final String name;
  final int code;
}

/// Reads the installed app's version. An interface so tests need no platform
/// channel.
abstract interface class InstalledApp {
  Future<InstalledVersion> version();
}

/// [InstalledApp] backed by `package_info_plus`.
class PackageInfoInstalledApp implements InstalledApp {
  const PackageInfoInstalledApp();

  @override
  Future<InstalledVersion> version() async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    return InstalledVersion(
      name: info.version,
      code: int.tryParse(info.buildNumber) ?? 0,
    );
  }
}

/// Opens a link outside the app (the phone's browser). An interface so tests
/// need no platform channel.
abstract interface class ExternalLinkOpener {
  /// Whether the link was handed to another app.
  Future<bool> open(Uri uri);
}

/// [ExternalLinkOpener] backed by `url_launcher`.
class UrlLauncherLinkOpener implements ExternalLinkOpener {
  const UrlLauncherLinkOpener();

  @override
  Future<bool> open(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}
