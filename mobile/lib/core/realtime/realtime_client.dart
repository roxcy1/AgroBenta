import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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
  /// Connect to Reverb and subscribe to the user's `private-user.{id}` channel
  /// plus the authenticated marketplace inventory channel. Returns once the
  /// connection and subscriptions are requested; events arrive asynchronously
  /// over [events]. Reconnection and re-subscription are handled by the client.
  Future<void> connect({required int userId});

  /// Disconnect and release the socket. Safe to call when already stopped.
  void disconnect();

  /// Checks the connection when the app returns to the foreground: a live
  /// channel emits `true` on [connected] (so screens re-fetch what they may
  /// have missed), a lost one is reconnected. No-op when not connected for a
  /// user.
  void checkConnection();

  /// Decoded events for the connected user's channel.
  Stream<RealtimeEvent> get events;

  /// Emits `true` whenever the user's private channel is (re)subscribed — not
  /// merely when the socket opens, because an open socket whose channel
  /// authorization failed delivers nothing — and `false` when the socket is
  /// lost. The app refreshes the affected data on `true` to recover events
  /// missed while offline (the package itself only re-subscribes channels).
  Stream<bool> get connected;
}

/// What [RealtimeClient.checkConnection] does on resume.
enum RealtimeResumeAction {
  /// The user channel is live: signal a resynchronising re-fetch.
  resync,

  /// A connection attempt is already in progress: let it finish.
  wait,

  /// Nothing is live: reconnect now rather than waiting for the backoff.
  reconnect,
}

/// Production [RealtimeClient] using `pusher_reverb_flutter`.
///
/// The bearer token is read from [TokenStore] on every private-channel
/// subscription, including the shared authenticated marketplace channel, so a
/// token change takes effect on the next subscription without recreating the
/// client. The token is never
/// logged or echoed.
class PusherReverbClient implements RealtimeClient {
  PusherReverbClient(this._tokenStore, {void Function(String message)? log})
    : _log = log ?? debugPrint;

  final TokenStore _tokenStore;

  /// Diagnostics sink. Only connection states, channel names and error
  /// descriptions are written — never the token or an event payload.
  final void Function(String message) _log;

  reverb.ReverbClient? _client;
  final Map<String, reverb.Channel> _channels = <String, reverb.Channel>{};
  final Map<String, StreamSubscription<reverb.ChannelEvent>>
  _eventSubscriptions = <String, StreamSubscription<reverb.ChannelEvent>>{};
  int? _currentUserId;

  final StreamController<RealtimeEvent> _events =
      StreamController<RealtimeEvent>.broadcast();
  final StreamController<bool> _connected = StreamController<bool>.broadcast();

  @override
  Stream<RealtimeEvent> get events => _events.stream;

  @override
  Stream<bool> get connected => _connected.stream;

  /// WebSocket ping frames on native platforms. A half-open socket (a network
  /// switch, a phone waking from sleep) misses the pong and is closed, which
  /// starts the package's automatic reconnect (exponential backoff, capped at
  /// 30 s) instead of sitting "connected" while delivering nothing. Browsers
  /// keep their own WebSocket alive; the setting is ignored on web.
  static const Duration heartbeatInterval = Duration(seconds: 20);

  /// The package's singleton client. Created once with stable configuration;
  /// its callbacks reference this instance, so they always act on the
  /// *current* session.
  reverb.ReverbClient _ensureClient() {
    final Uri uri = Uri.parse(AppConfig.reverbWsUrl);
    return reverb.ReverbClient.instance(
      host: uri.host,
      port: uri.port,
      appKey: AppConfig.reverbAppKey,
      useTLS: uri.scheme == 'wss',
      authEndpoint: '${AppConfig.apiOrigin}/broadcasting/auth',
      pingInterval: heartbeatInterval,
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
      // channel (idempotent). `connected` is reported from the channel's
      // subscription state (see [handleChannelState]), not from here.
      onConnected: (String? socketId) {
        if (_currentUserId == null) {
          // A reconnect the package had already scheduled completed after
          // sign-out. No session owns this socket, so close it.
          _log('Realtime: socket reconnected after sign-out; closing it.');
          _client?.disconnect();
          return;
        }
        _log('Realtime: socket connected; subscribing channels.');
        _subscribeToCurrentUser();
      },
      onDisconnected: () => _connected.add(false),
      // Socket errors and failed channel authorizations (401/403, CORS) end
      // up here. Without it a rejected subscription is completely silent.
      onError: (dynamic error) => _log('Realtime: ${describeError(error)}'),
    );
  }

  @override
  Future<void> connect({required int userId}) async {
    final reverb.ReverbClient client = _ensureClient();
    // The package cannot cancel a reconnect it has already scheduled. Opening
    // our own socket as well would leave two live connections fighting over
    // one client, so when one is pending we let it connect: `onConnected`
    // then subscribes whichever user is current by that time.
    final bool reconnectPending =
        client.connectionState == reverb.ConnectionState.reconnecting;

    // Drop any previous session's channels and listeners first, so nothing
    // from another account can reach this one.
    disconnect();
    _client = client;
    _currentUserId = userId;

    if (reconnectPending) {
      _log('Realtime: a reconnect is already scheduled; waiting for it.');
      return;
    }
    await client.connect();
  }

  @override
  void disconnect() {
    for (final StreamSubscription<reverb.ChannelEvent> subscription
        in _eventSubscriptions.values) {
      subscription.cancel();
    }
    _eventSubscriptions.clear();
    // Unsubscribe while the socket is still open. The package's own
    // `disconnect` closes the socket first and then unsubscribes each channel
    // into the closed sink, which surfaces as an unhandled "Cannot add event
    // after closing" error on every sign-out. A channel already unsubscribing
    // is skipped there. If the socket is already gone, the send fails here
    // and is ignored: the server dropped the subscription with the socket.
    for (final reverb.Channel channel in _channels.values) {
      unawaited(channel.unsubscribe().catchError((Object _) {}));
    }
    _channels.clear();
    _currentUserId = null;
    final reverb.ReverbClient? client = _client;
    if (client != null) {
      client.disconnect();
      // The singleton keeps the last socket id after a disconnect. A channel
      // authorized with it on the next socket is rejected by Reverb, so it is
      // cleared; the next `pusher:connection_established` sets the new one.
      client.socketId = null;
    }
    _client = null;
  }

  @override
  void checkConnection() {
    final reverb.ReverbClient? client = _client;
    final int? userId = _currentUserId;
    if (client == null || userId == null) {
      return;
    }

    switch (resumeActionFor(
      client.connectionState,
      _channels['private-user.$userId']?.state,
    )) {
      case RealtimeResumeAction.resync:
        // Live: events missed while the app was in the background (Android
        // may hold back socket traffic) are recovered by re-fetching.
        _log('Realtime: connection healthy on resume; resynchronising.');
        _connected.add(true);
      case RealtimeResumeAction.wait:
        _log('Realtime: reconnect in progress on resume.');
      case RealtimeResumeAction.reconnect:
        _log('Realtime: connection not live on resume; reconnecting.');
        unawaited(connect(userId: userId));
    }
  }

  /// What a resume should do, given the socket and user-channel state.
  ///
  /// The package's own reconnect is left alone while it is connecting or
  /// backing off (a second attempt would open a second socket). A connected
  /// socket whose user channel is not subscribed — its authorization failed,
  /// say — is reconnected so the subscription is retried with the current
  /// token.
  @visibleForTesting
  static RealtimeResumeAction resumeActionFor(
    reverb.ConnectionState connection,
    reverb.ChannelState? userChannel,
  ) {
    switch (connection) {
      case reverb.ConnectionState.connected:
        return userChannel == reverb.ChannelState.subscribed
            ? RealtimeResumeAction.resync
            : userChannel == reverb.ChannelState.subscribing
            ? RealtimeResumeAction.wait
            : RealtimeResumeAction.reconnect;
      case reverb.ConnectionState.connecting:
      case reverb.ConnectionState.reconnecting:
        return RealtimeResumeAction.wait;
      case reverb.ConnectionState.disconnected:
      case reverb.ConnectionState.error:
        return RealtimeResumeAction.reconnect;
    }
  }

  void _subscribeToCurrentUser() {
    final reverb.ReverbClient? client = _client;
    final int? userId = _currentUserId;
    if (client == null || userId == null) {
      return;
    }

    _subscribeToPrivateChannel(client, 'private-user.$userId');
    _subscribeToPrivateChannel(client, 'private-marketplace');
  }

  void _subscribeToPrivateChannel(
    reverb.ReverbClient client,
    String channelName,
  ) {
    // Guard each channel independently against duplicate subscriptions and
    // duplicate stream listeners on reconnect.
    if (_channels.containsKey(channelName)) {
      return;
    }

    final reverb.Channel channel = client.subscribeToPrivateChannel(
      channelName,
    );
    _channels[channelName] = channel;
    // Fires again on every reconnect, when the package re-subscribes.
    channel.addStateListener(
      (reverb.ChannelState state) => handleChannelState(channelName, state),
    );
    _eventSubscriptions[channelName] = channel.stream.listen(
      (reverb.ChannelEvent event) => handleChannelEvent(event),
    );
  }

  /// A channel subscription state change. Only a confirmed subscription
  /// (`pusher_internal:subscription_succeeded`) counts: the user's channel
  /// reports `connected = true`, which is the point at which events are live
  /// and a catch-up re-fetch cannot race a still-pending subscription.
  @visibleForTesting
  void handleChannelState(String channelName, reverb.ChannelState state) {
    if (state != reverb.ChannelState.subscribed) {
      return;
    }
    _log('Realtime: subscribed to $channelName.');
    if (channelName.startsWith('private-user.')) {
      _connected.add(true);
    }
  }

  /// A loggable description of a socket or subscription error. Built from the
  /// package's own messages, which carry the channel name and HTTP status but
  /// never the authorizer's headers.
  static String describeError(Object? error) {
    if (error is reverb.AuthenticationException) {
      final String status = error.statusCode == null
          ? ''
          : ' (HTTP ${error.statusCode})';
      return 'channel authorization failed$status for ${error.channelName}';
    }
    if (error is reverb.PusherException) {
      return error.message;
    }
    return 'error ${error.runtimeType}';
  }

  @visibleForTesting
  void handleChannelEvent(reverb.ChannelEvent event) {
    // Only channels this session subscribed. A late frame for a previous
    // account's channel (after sign-out or an account switch) is dropped, so
    // one user's events can never reach another user's screens.
    if (!_channels.containsKey(event.channelName)) {
      return;
    }

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
