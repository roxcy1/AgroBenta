import 'dart:async';

import 'package:agrobenta_mobile/core/realtime/realtime_client.dart';
import 'package:agrobenta_mobile/core/realtime/realtime_controller.dart';
import 'package:agrobenta_mobile/core/realtime/realtime_event.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRealtimeClient implements RealtimeClient {
  final List<int> connectCalls = <int>[];
  int disconnectCalls = 0;

  final StreamController<RealtimeEvent> _events =
      StreamController<RealtimeEvent>.broadcast();
  final StreamController<bool> _connected = StreamController<bool>.broadcast();

  /// When non-null, `connect` throws this after recording the call.
  Object? connectError;

  @override
  Stream<RealtimeEvent> get events => _events.stream;

  @override
  Stream<bool> get connected => _connected.stream;

  @override
  Future<void> connect({required int userId}) async {
    connectCalls.add(userId);
    final Object? error = connectError;
    if (error != null) {
      throw error;
    }
  }

  @override
  void disconnect() {
    disconnectCalls++;
  }

  void emit(RealtimeEvent event) => _events.add(event);

  void setConnected(bool value) => _connected.add(value);
}

void main() {
  group('RealtimeController', () {
    test('start connects for the given user', () async {
      final _FakeRealtimeClient client = _FakeRealtimeClient();
      final RealtimeController controller = RealtimeController(client);

      await controller.start(5);

      expect(client.connectCalls, <int>[5]);
      controller.dispose();
    });

    test('start is idempotent for the same user', () async {
      final _FakeRealtimeClient client = _FakeRealtimeClient();
      final RealtimeController controller = RealtimeController(client);

      await controller.start(5);
      await controller.start(5);

      expect(client.connectCalls, <int>[5]);
      controller.dispose();
    });

    test('start reconnects when the user changes', () async {
      final _FakeRealtimeClient client = _FakeRealtimeClient();
      final RealtimeController controller = RealtimeController(client);

      await controller.start(5);
      await controller.start(6);

      expect(client.connectCalls, <int>[5, 6]);
      controller.dispose();
    });

    test('stop disconnects', () async {
      final _FakeRealtimeClient client = _FakeRealtimeClient();
      final RealtimeController controller = RealtimeController(client);

      await controller.start(5);
      controller.stop();

      expect(client.disconnectCalls, 1);
      controller.dispose();
    });

    test('dispose disconnects', () async {
      final _FakeRealtimeClient client = _FakeRealtimeClient();
      final RealtimeController controller = RealtimeController(client);

      await controller.start(5);
      controller.dispose();

      expect(client.disconnectCalls, 1);
    });

    test('a connect failure does not throw', () async {
      final _FakeRealtimeClient client = _FakeRealtimeClient()
        ..connectError = Exception('reverb down');
      final RealtimeController controller = RealtimeController(client);

      // Must not throw: real-time is best-effort and never fails sign-in.
      await controller.start(5);

      expect(client.connectCalls, <int>[5]);
      controller.dispose();
    });

    test('events are forwarded to listeners', () async {
      final _FakeRealtimeClient client = _FakeRealtimeClient();
      final RealtimeController controller = RealtimeController(client);

      final List<RealtimeEvent> received = <RealtimeEvent>[];
      final StreamSubscription<RealtimeEvent> subscription =
          controller.events.listen(received.add);

      client.emit(const RealtimeEvent(name: 'message.sent', data: {'id': 1}));

      await Future<void>.delayed(Duration.zero);
      expect(received.single.name, 'message.sent');

      await subscription.cancel();
      controller.dispose();
    });

    test('connection changes are forwarded (for reconnect reconciliation)', () async {
      final _FakeRealtimeClient client = _FakeRealtimeClient();
      final RealtimeController controller = RealtimeController(client);

      final List<bool> received = <bool>[];
      final StreamSubscription<bool> subscription =
          controller.connected.listen(received.add);

      client.setConnected(true);
      client.setConnected(false);

      await Future<void>.delayed(Duration.zero);
      expect(received, <bool>[true, false]);

      await subscription.cancel();
      controller.dispose();
    });
  });
}
