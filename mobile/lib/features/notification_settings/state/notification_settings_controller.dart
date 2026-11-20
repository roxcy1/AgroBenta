import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../models/notification_preferences.dart';
import '../../../repositories/notification_repository.dart';

enum NotificationSettingsStatus { loading, ready, failed }

/// State for the Notification Settings screen.
///
/// A switch changes on screen straight away and is then saved; if the save
/// fails it goes back and [saveError] says so. One save per category runs at a
/// time, so a switch is disabled while its own save is in flight.
class NotificationSettingsController extends ChangeNotifier {
  NotificationSettingsController(this._repository);

  final NotificationRepository _repository;

  NotificationSettingsStatus _status = NotificationSettingsStatus.loading;
  NotificationPreferences? _preferences;
  String? _loadError;
  String? _saveError;
  final Set<NotificationCategory> _saving = <NotificationCategory>{};
  bool _disposed = false;

  NotificationSettingsStatus get status => _status;
  NotificationPreferences? get preferences => _preferences;
  String? get loadError => _loadError;

  /// The last failed save's message, until [clearSaveError].
  String? get saveError => _saveError;

  bool isSaving(NotificationCategory category) => _saving.contains(category);

  Future<void> load() async {
    _status = NotificationSettingsStatus.loading;
    _loadError = null;
    _notify();
    try {
      _preferences = await _repository.preferences();
      _status = NotificationSettingsStatus.ready;
    } on ApiException catch (error) {
      _loadError = error.message;
      _status = NotificationSettingsStatus.failed;
    } on Object {
      _loadError = 'Something went wrong. Please try again.';
      _status = NotificationSettingsStatus.failed;
    }
    _notify();
  }

  Future<void> setEnabled(
    NotificationCategory category, {
    required bool enabled,
  }) async {
    final NotificationPreferences? previous = _preferences;
    if (previous == null ||
        _saving.contains(category) ||
        previous.isEnabled(category) == enabled) {
      return;
    }

    _preferences = previous.withCategory(category, enabled: enabled);
    _saving.add(category);
    _saveError = null;
    _notify();

    try {
      final NotificationPreferences saved = await _repository.updatePreference(
        category,
        enabled: enabled,
      );
      // Only this category is taken from the reply: another switch may have
      // changed on screen while this request was in flight.
      _preferences = _preferences?.withCategory(
        category,
        enabled: saved.isEnabled(category),
      );
    } on Object catch (error) {
      _preferences = _preferences?.withCategory(
        category,
        enabled: previous.isEnabled(category),
      );
      _saveError = error is ApiException
          ? error.message
          : 'Could not save your notification settings. Please try again.';
    } finally {
      _saving.remove(category);
      _notify();
    }
  }

  void clearSaveError() {
    _saveError = null;
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
