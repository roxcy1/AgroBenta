import 'package:agrobenta_mobile/core/realtime/realtime_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pusher_reverb_flutter/pusher_reverb_flutter.dart' as reverb;

import '../../support/auth_fakes.dart';

void main() {
  group('PusherReverbClient subscription state', () {
    late List<String> logs;
    late PusherReverbClient client;
    late List<bool> connected;

    setUp(() {
      logs = <String>[];
      connected = <bool>[];
      client = PusherReverbClient(FakeTokenStore(), log: logs.add);
      client.connected.listen(connected.add);
    });

    test(
      'reports connected only once the user channel is subscribed',
      () async {
        client.handleChannelState(
          'private-user.5',
          reverb.ChannelState.subscribing,
        );
        await Future<void>.delayed(Duration.zero);
        expect(connected, isEmpty);

        client.handleChannelState(
          'private-user.5',
          reverb.ChannelState.subscribed,
        );
        await Future<void>.delayed(Duration.zero);
        expect(connected, <bool>[true]);
        expect(logs, contains('Realtime: subscribed to private-user.5.'));
      },
    );

    test(
      'a marketplace subscription is logged but is not "connected"',
      () async {
        client.handleChannelState(
          'private-marketplace',
          reverb.ChannelState.subscribed,
        );
        await Future<void>.delayed(Duration.zero);

        expect(connected, isEmpty);
        expect(logs, contains('Realtime: subscribed to private-marketplace.'));
      },
    );

    test(
      'a failed resubscription (back to unsubscribed) reports nothing',
      () async {
        client.handleChannelState(
          'private-user.5',
          reverb.ChannelState.unsubscribed,
        );
        await Future<void>.delayed(Duration.zero);

        expect(connected, isEmpty);
        expect(logs, isEmpty);
      },
    );
  });

  group('PusherReverbClient.resumeActionFor', () {
    RealtimeResumeAction action(
      reverb.ConnectionState connection, [
      reverb.ChannelState? channel,
    ]) => PusherReverbClient.resumeActionFor(connection, channel);

    test('a live user channel resynchronises', () {
      expect(
        action(
          reverb.ConnectionState.connected,
          reverb.ChannelState.subscribed,
        ),
        RealtimeResumeAction.resync,
      );
    });

    test('a pending subscription or connection is left to finish', () {
      expect(
        action(
          reverb.ConnectionState.connected,
          reverb.ChannelState.subscribing,
        ),
        RealtimeResumeAction.wait,
      );
      expect(
        action(reverb.ConnectionState.connecting),
        RealtimeResumeAction.wait,
      );
      expect(
        action(reverb.ConnectionState.reconnecting),
        RealtimeResumeAction.wait,
        reason: 'never a second socket beside the scheduled reconnect',
      );
    });

    test('a socket whose user channel is not live reconnects', () {
      expect(
        action(
          reverb.ConnectionState.connected,
          reverb.ChannelState.unsubscribed,
        ),
        RealtimeResumeAction.reconnect,
      );
      expect(
        action(reverb.ConnectionState.connected),
        RealtimeResumeAction.reconnect,
      );
    });

    test('a lost or failed socket reconnects', () {
      expect(
        action(reverb.ConnectionState.disconnected),
        RealtimeResumeAction.reconnect,
      );
      expect(
        action(reverb.ConnectionState.error),
        RealtimeResumeAction.reconnect,
      );
    });
  });

  group('PusherReverbClient session isolation', () {
    test(
      'drops an event from a channel this session did not subscribe',
      () async {
        final PusherReverbClient client = PusherReverbClient(
          FakeTokenStore(),
          log: (_) {},
        );
        final List<String> received = <String>[];
        client.events.listen((event) => received.add(event.name));

        // e.g. a late frame for the previous account after an account switch.
        client.handleChannelEvent(
          reverb.ChannelEvent(
            channelName: 'private-user.99',
            eventName: 'message.sent',
            data: '{"id":1,"sender_id":3}',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(received, isEmpty);
      },
    );

    test('checkConnection is a no-op before any session', () {
      final List<String> logs = <String>[];
      final PusherReverbClient client = PusherReverbClient(
        FakeTokenStore(),
        log: logs.add,
      );

      client.checkConnection();

      expect(logs, isEmpty);
    });

    test('the heartbeat detects a dead socket well inside Reverb timeouts', () {
      // Reverb pings an idle client every 60 s; a half-open socket must be
      // noticed sooner than that.
      expect(
        PusherReverbClient.heartbeatInterval,
        lessThan(const Duration(seconds: 60)),
      );
    });
  });

  group('PusherReverbClient.describeError', () {
    test('names the channel and HTTP status of a rejected authorization', () {
      final String description = PusherReverbClient.describeError(
        reverb.AuthenticationException(
          message: 'Authentication forbidden - insufficient permissions',
          channelName: 'private-user.5',
          statusCode: 403,
        ),
      );

      expect(
        description,
        'channel authorization failed (HTTP 403) for private-user.5',
      );
      expect(description, isNot(contains('Bearer')));
    });

    test('keeps the channel and status of a refused subscription as the package reports it', () {
      // The package wraps a failed channel authorization in a
      // ConnectionException whose message embeds the AuthenticationException.
      const reverb.AuthenticationException refused =
          reverb.AuthenticationException(
            message: 'Authentication forbidden - insufficient permissions',
            channelName: 'private-user.5',
            statusCode: 403,
          );
      final String description = PusherReverbClient.describeError(
        reverb.ConnectionException('Failed to subscribe to private-user.5: $refused'),
      );

      expect(description, contains('private-user.5'));
      expect(description, contains('(HTTP 403)'));
      expect(description, isNot(contains('Bearer')));
    });

    test('uses the package message for socket errors, not the cause', () {
      final String description = PusherReverbClient.describeError(
        reverb.ConnectionException(
          'WebSocket error occurred',
          cause: 'ws://host:8083/app/key?token=secret',
        ),
      );

      expect(description, 'WebSocket error occurred');
      expect(description, isNot(contains('secret')));
    });

    test('falls back to the type for anything else', () {
      expect(
        PusherReverbClient.describeError(StateError('boom')),
        'error StateError',
      );
    });
  });

  group('PusherReverbClient.decodeData', () {
    test('decodes the double-encoded JSON string payload', () {
      final Map<String, dynamic> data = PusherReverbClient.decodeData(
        '{"id":5,"body":"hello"}',
      );

      expect(data, <String, dynamic>{'id': 5, 'body': 'hello'});
    });

    test('passes through an already-decoded map', () {
      const Map<String, dynamic> data = <String, dynamic>{'id': 5};

      expect(PusherReverbClient.decodeData(data), same(data));
    });

    test('returns empty for malformed JSON', () {
      expect(PusherReverbClient.decodeData('not-json'), isEmpty);
    });

    test('returns empty for a non-string, non-map value', () {
      expect(PusherReverbClient.decodeData(42), isEmpty);
      expect(PusherReverbClient.decodeData(null), isEmpty);
      expect(PusherReverbClient.decodeData(''), isEmpty);
    });
  });
}
