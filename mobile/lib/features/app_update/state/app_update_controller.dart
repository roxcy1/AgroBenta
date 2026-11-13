import 'package:flutter/foundation.dart';

import '../../../core/platform/installed_app.dart';
import '../../../models/app_release.dart';
import '../../../repositories/app_release_repository.dart';

enum AppUpdateStatus {
  /// Nothing checked yet.
  idle,
  checking,

  /// The installed build is the latest one, or nothing is published yet.
  upToDate,
  updateAvailable,

  /// The check failed (offline, server error); the user can retry.
  failed,
}

/// The App Update tile's state: the installed version and, after a check,
/// whether the server has a newer build.
///
/// Owned by the tile and disposed with it. It checks once when the tile
/// appears and again when the user taps the tile.
class AppUpdateController extends ChangeNotifier {
  AppUpdateController(this._repository);

  final AppReleaseRepository _repository;

  AppUpdateStatus _status = AppUpdateStatus.idle;
  InstalledVersion? _installed;
  AppRelease? _latest;
  bool _opening = false;
  bool _disposed = false;

  AppUpdateStatus get status => _status;
  InstalledVersion? get installed => _installed;

  /// The newer release, when [status] is [AppUpdateStatus.updateAvailable].
  AppRelease? get latest => _latest;
  bool get isOpeningDownload => _opening;

  Future<void> check() async {
    if (_status == AppUpdateStatus.checking) {
      return;
    }
    _status = AppUpdateStatus.checking;
    _notify();

    try {
      _installed ??= await _repository.installedVersion();
      final AppUpdateCheck result = await _repository.check();
      _installed = result.installed;
      _latest = result.updateAvailable ? result.latest : null;
      _status = result.updateAvailable
          ? AppUpdateStatus.updateAvailable
          : AppUpdateStatus.upToDate;
    } catch (error) {
      debugPrint('App update check failed: ${error.runtimeType}');
      _latest = null;
      _status = AppUpdateStatus.failed;
    }
    _notify();
  }

  /// Opens the newer release's download. False when there is nothing to open
  /// or the phone could not open the link.
  Future<bool> openDownload() async {
    final AppRelease? release = _latest;
    if (release == null || _opening) {
      return false;
    }
    _opening = true;
    _notify();
    try {
      return await _repository.openDownload(release);
    } catch (error) {
      debugPrint('Opening the app download failed: ${error.runtimeType}');
      return false;
    } finally {
      _opening = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
