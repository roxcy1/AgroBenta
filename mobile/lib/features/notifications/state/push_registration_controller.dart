import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/push/push_messaging.dart';
import '../../../repositories/device_repository.dart';

/// Keeps this phone registered for push while a user is signed in.
///
/// [start] runs when a session begins: it asks for notification permission,
/// sends the FCM token to the backend, and re-sends any refreshed token.
/// [stop] runs when the session ends: it stops listening and invalidates the
/// FCM token, so the next account signed in on this phone gets its own. The
/// backend has already dropped the old registration with the session token.
///
/// Push is a convenience: every failure here is logged and swallowed, so it
/// can never block or break signing in.
class PushRegistrationController {
  PushRegistrationController(this._messaging, this._repository);

  final PushMessaging _messaging;
  final DeviceRepository _repository;

  StreamSubscription<String>? _refreshSubscription;

  /// Bumped by every [start] and [stop], so a slow permission prompt or token
  /// request from an ended session cannot register for the next one.
  int _generation = 0;

  /// [start] and [stop] run one after another, never overlapping: switching
  /// accounts must finish deleting the old token before asking for a new one.
  Future<void> _queue = Future<void>.value();

  Future<void> start() {
    final int generation = ++_generation;
    return _queue = _queue.then((_) => _start(generation));
  }

  Future<void> stop() {
    _generation++;
    return _queue = _queue.then((_) => _stop());
  }

  Future<void> _start(int generation) async {
    if (generation != _generation) {
      return;
    }
    await _refreshSubscription?.cancel();
    _refreshSubscription = null;

    try {
      final String? token = await _messaging.requestPermissionAndGetToken();
      if (generation != _generation || token == null) {
        return;
      }
      await _repository.registerPushToken(token);
    } catch (error) {
      debugPrint('Push registration failed: ${error.runtimeType}');
    }

    if (generation != _generation) {
      return;
    }
    _refreshSubscription = _messaging.onTokenRefresh.listen(
      (String token) => _register(token, generation),
      onError: (Object error) =>
          debugPrint('Push token refresh failed: ${error.runtimeType}'),
    );
  }

  Future<void> _stop() async {
    await _refreshSubscription?.cancel();
    _refreshSubscription = null;

    try {
      await _messaging.deleteToken();
    } catch (error) {
      debugPrint('Push token removal failed: ${error.runtimeType}');
    }
  }

  Future<void> _register(String token, int generation) async {
    if (generation != _generation) {
      return;
    }
    try {
      await _repository.registerPushToken(token);
    } catch (error) {
      debugPrint('Push registration failed: ${error.runtimeType}');
    }
  }

  void dispose() {
    _generation++;
    _refreshSubscription?.cancel();
    _refreshSubscription = null;
  }
}
