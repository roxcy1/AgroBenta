import 'dart:async';
import 'dart:convert';

import 'package:pusher_reverb_flutter/pusher_reverb_flutter.dart' as reverb;

import '../config/app_config.dart';
import '../storage/token_store.dart';
import 'realtime_event.dart';

/// The real-time transport — the WebSocket analogue of `ApiClient`.
///
/// Feature code depends on this narrow interface so a fake can replace it in
/// tests, exactly as `TokenStore` abstracts `flutter_secure_storage`.
/// [PusherReverbClient] is the production implementation backed by the
/// `pusher_reverb_flutter` package.
abstract interface class RealtimeClient {
  /// Connect to Reverb and subscribe to the user's `private-user.{id}`
  /// channel. Returns once the connection and subscription are requested;
  /// events arrive asynchronously over [events]. Reconnection (and
  /// re-subscription) is handled by the underlying client.
  Future<void> connect({required int userId});

  /// Disconnect and release the socket. Safe to call when already stopped.
  void disconnect();

  /// Decoded events for the connected user's channel.
  Stream<RealtimeEvent> get events;

  /// Emits `true` whenever the socket (re)connects and `false` when it is
  /// lost. The app refreshes the affected data on `true` to recover events
  /// missed while offline (the package itself only re-subscribes channels).
  Stream<bool> get connected;
}

/// Production [RealtimeClient] using `pusher_reverb_flutter`.
///
/// The bearer token is read from [TokenStore] on every private-channel
/// subscription, so a token change (sign-out / new account) takes effect on
/// the next subscription without recreating the client. The token is never
/// logged or echoed.
class PusherReverbClient implements RealtimeClient {
  PusherReverbClient(this._tokenStore);

  final TokenStore _tokenStore;

  reverb.ReverbClient? _client;
  reverb.Channel? _channel;
  StreamSubscription<reverb.ChannelEvent>? _eventSubscription;
  int? _currentUserId;

  final StreamController<RealtimeEvent> _events =
      StreamController<RealtimeEvent>.broadcast();
  final StreamController<bool> _connected = StreamController<bool>.broadcast();

  @override
  Stream<RealtimeEvent> get events => _events.stream;

  @override
  Stream<bool> get connected => _connected.stream;

  @override
  Future<void> connect({required int userId}) async {
    // Drop any previous connection/channel (a different user, or a reconnect)
    // before establishing the new one.
    disconnect();

    _currentUserId = userId;

    final Uri uri = Uri.parse(AppConfig.reverbWsUrl);

    // The singleton is created once with stable config and an authorizer that
    // reads the token lazily. The `onConnected` callback references the
    // instance method, so it always subscribes the *current* user.
    final reverb.ReverbClient client = reverb.ReverbClient.instance(
      host: uri.host,
      port: uri.port,
      appKey: AppConfig.reverbAppKey,
      useTLS: uri.scheme == 'wss',
      authEndpoint: '${AppConfig.apiOrigin}/broadcasting/auth',
      authorizer: (String channelName, String socketId) async {
        final String? token = await _tokenStore.read();
        if (token == null || token.isEmpty) {
          return const <String, String>{};
        }
        return <String, String>{'Authorization': 'Bearer $token'};
      },
      // `subscribeToPrivateChannel` needs the socket id, which is known only
      // after `pusher:connection_established`. Subscribe then; the callback
      // also re-fires on reconnect, where the package re-subscribes the same
      // channel (idempotent) and the app re-fetches any missed events.
      onConnected: (String? socketId) {
        _connected.add(true);
        _subscribeToCurrentUser();
      },
      onDisconnected: () => _connected.add(false),
    );

    _client = client;

    await client.connect();

    // Already-connected fast path (re-using a live socket): subscribe now.
    if (client.socketId != null) {
      _subscribeToCurrentUser();
    }
  }

  @override
  void disconnect() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _channel = null;
    _currentUserId = null;
    _client?.disconnect();
    _client = null;
  }

  void _subscribeToCurrentUser() {
    final reverb.ReverbClient? client = _client;
    final int? userId = _currentUserId;
    if (client == null || userId == null) {
      return;
    }

    final String channelName = 'private-user.$userId';

    // Guard against a duplicate subscription / duplicate stream listener.
    if (_channel?.name == channelName) {
      return;
    }

    final reverb.Channel channel = client.subscribeToPrivateChannel(channelName);
    _channel = channel;

    _eventSubscription?.cancel();
    _eventSubscription = channel.stream.listen(
      (reverb.ChannelEvent event) => _onChannelEvent(event),
    );
  }

  void _onChannelEvent(reverb.ChannelEvent event) {
    // Ignore the protocol-level events the client surfaces; only server
    // broadcast events (`message.sent`, `transaction.updated`, …) matter here.
    if (event.eventName.startsWith('pusher:') ||
        event.eventName.startsWith('pusher_internal:')) {
      return;
    }

    final Map<String, dynamic> data = decodeData(event.data);
    if (data.isEmpty) {
      return;
    }

    _events.add(RealtimeEvent(name: event.eventName, data: data));
  }

  /// The Pusher protocol double-encodes the payload, so `data` is normally a
  /// JSON string. Decode it defensively, tolerating an already-decoded map.
  ///
  /// Public (rather than private) so the decoding is unit-testable without a
  /// live socket.
  static Map<String, dynamic> decodeData(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is String && data.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      } on FormatException {
        return const <String, dynamic>{};
      }
    }
    return const <String, dynamic>{};
  }
}
