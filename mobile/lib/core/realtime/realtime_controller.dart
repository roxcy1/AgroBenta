import 'package:flutter/foundation.dart';

import 'realtime_client.dart';
import 'realtime_event.dart';

/// Owns the real-time connection for the signed-in session.
///
/// Long-lived (created once in the composition root), but connected only while
/// a user is signed in: `start(userId)` on sign-in, `stop()` on sign-out. The
/// connection is best-effort — a failure must never fail sign-in or any
/// feature, because the REST API remains the source of truth and the screens
/// already recover via pull-to-refresh.
class RealtimeController extends ChangeNotifier {
  RealtimeController(this._client);

  final RealtimeClient _client;

  int? _userId;

  /// Decoded events for the connected user. Feature wiring (in `main.dart`)
  /// listens to this and re-fetches the affected data over REST.
  Stream<RealtimeEvent> get events => _client.events;

  /// Connection changes. The app refreshes on `true` to recover events missed
  /// while the socket was down.
  Stream<bool> get connected => _client.connected;

  /// Connect (or do nothing when already connected for [userId]).
  Future<void> start(int userId) async {
    if (_userId == userId) {
      return;
    }
    _userId = userId;

    try {
      await _client.connect(userId: userId);
    } catch (_) {
      // Best-effort: the underlying client keeps retrying on its own, and the
      // app is fully usable over REST without a live socket.
    }
  }

  /// Disconnect and forget the current user.
  void stop() {
    _userId = null;
    _client.disconnect();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
