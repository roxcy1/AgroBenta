import 'dart:async';

import 'package:flutter/widgets.dart';

/// The app's foreground state, as one session-wide signal.
///
/// Polling controllers take [changes] as a `Stream<bool>` and pause while the
/// app is not in front of the user. Android and iOS can suspend or kill a
/// backgrounded process at any moment, so a timer that keeps firing there
/// spends battery and data on responses the user will never see; it also
/// risks a burst of catch-up requests when the app returns.
///
/// [AppLifecycleState.resumed] is the only visible state. `inactive`,
/// `hidden`, `paused` and `detached` all mean "not visible" — `inactive`
/// fires during the transition into the background (an incoming call, the
/// app switcher, the notification shade), which is exactly when polling
/// should stop. The same rule is used by `AccountModeShell`.
///
/// One instance is created in `main.dart` and registered as a
/// [WidgetsBindingObserver]. The constructor requires an initialised binding.
class AppVisibility with WidgetsBindingObserver {
  AppVisibility({bool initiallyActive = true}) : _isActive = initiallyActive {
    WidgetsBinding.instance.addObserver(this);
  }

  final StreamController<bool> _changes = StreamController<bool>.broadcast();

  bool _isActive;
  bool _disposed = false;

  /// Whether the app is currently in front of the user.
  bool get isActive => _isActive;

  /// Emits only on a real transition, so a pause/resume pair that was already
  /// reported is not repeated.
  Stream<bool> get changes => _changes.stream;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _update(state == AppLifecycleState.resumed);
  }

  void _update(bool active) {
    if (_disposed || active == _isActive) {
      return;
    }
    _isActive = active;
    _changes.add(active);
  }

  /// Detaches from the binding and closes [changes].
  ///
  /// Safe to call more than once, so `main.dart` can dispose it without
  /// tracking whether it was already torn down.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _changes.close();
  }
}
