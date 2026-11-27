import 'dart:async';

/// Coalesces the background refreshes that real-time events request.
///
/// Events arrive in bursts (a message and its notification, two quick
/// messages), and a controller that simply ignores a request while a load is
/// in flight loses the event that arrived during that load. This runs at most
/// one refresh at a time, and a request that arrives while a refresh — or any
/// other load the owner reports through `isBusy` — is in flight is remembered
/// and answered by exactly **one** trailing refresh. The result always reflects
/// the latest event, with no overlapping requests and no unbounded queue.
///
/// The owner calls [settled] when a load it started itself (a first load,
/// pull-to-refresh) finishes, so a request deferred behind that load runs.
class RefreshCoalescer {
  RefreshCoalescer(this._refresh, {required this.isBusy});

  /// The background refresh. Expected to report its own failures in state;
  /// anything it throws is swallowed so a burst can never surface an
  /// unhandled error.
  final Future<void> Function() _refresh;

  /// Whether the owner has a load of the same data in flight.
  final bool Function() isBusy;

  bool _running = false;
  bool _pending = false;
  bool _disposed = false;

  /// Asks for a refresh now, or as soon as the in-flight work settles.
  void request() {
    if (_disposed) {
      return;
    }
    if (_running || isBusy()) {
      _pending = true;
      return;
    }
    unawaited(_drain());
  }

  /// The owner's own load finished; run a refresh that was deferred behind it.
  void settled() {
    if (_disposed || _running || !_pending || isBusy()) {
      return;
    }
    unawaited(_drain());
  }

  /// Stops all further refreshes. Safe to call more than once.
  void dispose() {
    _disposed = true;
    _pending = false;
  }

  Future<void> _drain() async {
    _running = true;
    try {
      while (!_disposed) {
        _pending = false;
        try {
          await _refresh();
        } on Object {
          // The refresh owns its error reporting; see [_refresh].
        }
        // Stop when nothing new arrived. Also stop when the owner started a
        // load of its own meanwhile: the request stays pending and that load's
        // [settled] answers it, so the two never overlap.
        if (!_pending || isBusy()) {
          break;
        }
      }
    } finally {
      _running = false;
    }
  }
}
