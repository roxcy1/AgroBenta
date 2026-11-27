// Live real-time end-to-end test: the app's real PusherReverbClient,
// RealtimeController and screen controllers over real HTTP and WebSocket.
//
// Skipped unless a fixture is supplied. It needs a running backend with
// Reverb and a queue worker, seeded throwaway accounts, and (for the outage
// step) the `docker` CLI on PATH, run from the repository's `mobile/`:
//
//   flutter test test/e2e/realtime_live_test.dart \
//     --dart-define=E2E_FIXTURE=<path to fixture.json> \
//     --dart-define=API_BASE_URL=http://localhost:8090/api \
//     --dart-define=REVERB_WS_URL=ws://localhost:8083
//
// The fixture is `{seller, buyer, buyer2: {id, token}, listing_id}`. Never
// point it at real accounts: the test sends messages and moves a transaction.
// `docs/features/reverb-integration.md` documents the isolated e2e stack.
import 'dart:convert';
import 'dart:io';

import 'package:agrobenta_mobile/core/config/app_config.dart';
import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/core/realtime/realtime_client.dart';
import 'package:agrobenta_mobile/core/realtime/realtime_controller.dart';
import 'package:agrobenta_mobile/core/realtime/realtime_event.dart';
import 'package:agrobenta_mobile/features/marketplace/state/marketplace_controller.dart';
import 'package:agrobenta_mobile/features/messaging/state/chat_controller.dart';
import 'package:agrobenta_mobile/features/messaging/state/messaging_state.dart';
import 'package:agrobenta_mobile/features/notifications/state/notifications_controller.dart';
import 'package:agrobenta_mobile/features/notifications/state/notifications_state.dart';
import 'package:agrobenta_mobile/features/transactions/state/transaction_detail_controller.dart';
import 'package:agrobenta_mobile/features/transactions/state/transaction_detail_state.dart';
import 'package:agrobenta_mobile/repositories/marketplace_repository.dart';
import 'package:agrobenta_mobile/repositories/messaging_repository.dart';
import 'package:agrobenta_mobile/repositories/notification_repository.dart';
import 'package:agrobenta_mobile/repositories/transaction_repository.dart';
import 'package:agrobenta_mobile/services/marketplace_service.dart';
import 'package:agrobenta_mobile/services/messaging_service.dart';
import 'package:agrobenta_mobile/services/notification_service.dart';
import 'package:agrobenta_mobile/services/transaction_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/auth_fakes.dart';

const String _fixturePath = String.fromEnvironment('E2E_FIXTURE');

/// Counts requests per API path, so a test can see a refresh happen.
class _CountingClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  final Map<String, int> counts = <String, int>{};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final String path = request.url.path.replaceFirst(RegExp(r'^/api'), '');
    counts[path] = (counts[path] ?? 0) + 1;
    return _inner.send(request);
  }

  int of(String path) => counts[path] ?? 0;
}

/// Waits until [condition] holds, re-checking on every change and every
/// 100 ms, or fails after [timeout].
Future<void> eventually(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
  String reason = '',
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out after ${timeout.inSeconds}s: $reason');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  group('Live real-time E2E', _liveTests,
      skip: _fixturePath.isEmpty
          ? 'needs --dart-define=E2E_FIXTURE (see the file header)'
          : null);
}

void _liveTests() {
  late Map<String, dynamic> fixture;
  late int sellerId, buyerId, buyer2Id;
  late String sellerToken, buyerToken, buyer2Token;

  late FakeTokenStore tokenStore;
  late _CountingClient counting;
  late ApiClient api;
  late List<String> logs;
  late PusherReverbClient client;
  late RealtimeController realtime;
  final List<bool> connections = <bool>[];
  final List<RealtimeEvent> events = <RealtimeEvent>[];

  /// A request as another account (the counterpart acting on its own phone).
  Future<Map<String, dynamic>> as(
    String token,
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final Uri uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
    final Map<String, String> headers = <String, String>{
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    final http.Response res = method == 'GET'
        ? await http.get(uri, headers: headers)
        : await http.post(uri, headers: headers, body: jsonEncode(body ?? {}));
    expect(res.statusCode, lessThan(300), reason: '$method $path: ${res.body}');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<int> sendMessage(String token, int to, String body) async =>
      ((await as(token, 'POST', '/messages', <String, dynamic>{
                'receiver_id': to,
                'body': body,
              }))['data']
              as Map<String, dynamic>)['id']
          as int;

  int subscriptionsTo(String channel) =>
      logs.where((String l) => l == 'Realtime: subscribed to $channel.').length;

  setUpAll(() async {
    // flutter_test replaces HttpClient with a mock that answers 400; this test
    // is about the real network, so restore the platform client.
    HttpOverrides.global = null;

    fixture =
        jsonDecode(await File(_fixturePath).readAsString())
            as Map<String, dynamic>;
    final Map<String, dynamic> seller =
        fixture['seller'] as Map<String, dynamic>;
    final Map<String, dynamic> buyer = fixture['buyer'] as Map<String, dynamic>;
    final Map<String, dynamic> buyer2 =
        fixture['buyer2'] as Map<String, dynamic>;
    sellerId = seller['id'] as int;
    sellerToken = seller['token'] as String;
    buyerId = buyer['id'] as int;
    buyerToken = buyer['token'] as String;
    buyer2Id = buyer2['id'] as int;
    buyer2Token = buyer2['token'] as String;

    tokenStore = FakeTokenStore(buyerToken);
    counting = _CountingClient();
    api = ApiClient(tokenStorage: tokenStore, httpClient: counting);
    logs = <String>[];
    client = PusherReverbClient(tokenStore, log: logs.add);
    realtime = RealtimeController(client);
    realtime.connected.listen(connections.add);
    realtime.events.listen(events.add);
  });

  tearDownAll(() {
    realtime.dispose();
  });

  test('the buyer connects and its user channel subscription is confirmed', () async {
    await realtime.start(buyerId);

    await eventually(
      () => connections.contains(true),
      reason: 'connected=true only after subscription_succeeded',
    );
    expect(subscriptionsTo('private-user.$buyerId'), 1);
    expect(logs.any((String l) => l.contains('authorization failed')), isFalse);
  });

  group('open screens update without a manual refresh', () {
    late ChatController chat;
    final List<ChatStatus> chatStatuses = <ChatStatus>[];

    setUpAll(() async {
      chat = ChatController(
        MessagingRepository(MessagingService(api)),
        counterpartId: sellerId,
        currentUserId: buyerId,
        realtimeEvents: realtime.events,
        connection: realtime.connected,
        isVisible: () => true,
      );
      await chat.load();
      chat.addListener(() => chatStatuses.add(chat.state.status));
    });

    tearDownAll(() => chat.dispose());

    bool chatHas(int id) => chat.state.messages.any((m) => m.id == id);

    test('three rapid messages appear in the open chat and are read', () async {
      final List<int> ids = <int>[
        for (int i = 0; i < 3; i++)
          await sendMessage(sellerToken, buyerId, 'Live E2E $i'),
      ];

      await eventually(
        () => ids.every(chatHas),
        reason: 'messages delivered via message.sent → silent refresh',
      );
      expect(chatStatuses, isNot(contains(ChatStatus.loading)));

      // Visible thread: the incoming messages were marked read on the server.
      await eventually(() {
        return chat.state.messages
            .where((m) => ids.contains(m.id))
            .every((m) => m.read);
      }, reason: 'marked read locally');
      final List<dynamic> conversations =
          (await as(buyerToken, 'GET', '/conversations'))['data']['conversations']
              as List<dynamic>;
      final Map<String, dynamic> withSeller =
          conversations.cast<Map<String, dynamic>>().firstWhere(
            (c) => (c['counterpart'] as Map<String, dynamic>)['id'] == sellerId,
          );
      expect(withSeller['unread_count'], 0, reason: 'read on the server');
    });

    test('a fulfillment step updates the transaction and notifications live', () async {
      final List<dynamic> sales =
          (await as(sellerToken, 'GET', '/transactions?role=seller'))['data']['transactions']
              as List<dynamic>;
      final int txId = (sales.first as Map<String, dynamic>)['id'] as int;

      final NotificationsController notifications = NotificationsController(
        NotificationRepository(NotificationService(api)),
        realtimeEvents: realtime.events,
      );
      final TransactionDetailController detail = TransactionDetailController(
        TransactionRepository(TransactionService(api)),
        txId,
        realtimeEvents: realtime.events,
        connection: realtime.connected,
      );
      addTearDown(notifications.dispose);
      addTearDown(detail.dispose);
      await notifications.load();
      await detail.load();
      final int notificationsBefore = notifications.state.notifications.length;
      final List<Object> states = <Object>[];
      notifications.addListener(() => states.add(notifications.state.status));
      detail.addListener(() => states.add(detail.state.status));

      await as(sellerToken, 'POST', '/transactions/$txId/ready-for-pickup');

      await eventually(
        () => detail.state.transaction?.fulfillmentStatusValue == 'ready_for_pickup',
        reason: 'transaction.updated → detail refresh',
      );
      await eventually(
        () => notifications.state.notifications.length > notificationsBefore,
        reason: 'notification.created → list refresh',
      );
      expect(states, isNot(contains(NotificationsStatus.loading)));
      expect(states, isNot(contains(TransactionDetailStatus.loading)));
    });

    test('an inventory change refreshes the open marketplace', () async {
      final MarketplaceController marketplace = MarketplaceController(
        MarketplaceRepository(MarketplaceService(api)),
        realtimeEvents: realtime.events,
      );
      addTearDown(marketplace.dispose);
      await marketplace.loadInitial();
      final int before = counting.of('/listings');

      // Another buyer reserves a head: the listing's availability changes.
      await as(buyer2Token, 'POST', '/transactions', <String, dynamic>{
        'listing_id': fixture['listing_id'],
        'quantity': 1,
      });

      await eventually(
        () => counting.of('/listings') > before,
        reason: 'listing.inventory.updated → marketplace refresh',
      );
    });

    test('after a Reverb outage the client reconnects, resubscribes once and recovers the missed message', () async {
      final int subscribedBefore = subscriptionsTo('private-user.$buyerId');
      connections.clear();

      final Future<ProcessResult> restart = Process.run(
        'docker',
        <String>['compose', 'restart', 'reverb'],
        workingDirectory: '..',
      );
      await eventually(
        () => connections.contains(false),
        timeout: const Duration(seconds: 30),
        reason: 'socket loss observed',
      );
      // Sent while the client is offline: the broadcast cannot reach it.
      final int missed = await sendMessage(sellerToken, buyerId, 'Sent during outage');
      expect((await restart).exitCode, 0);

      await eventually(
        () => connections.isNotEmpty && connections.last,
        timeout: const Duration(seconds: 60),
        reason: 'automatic reconnect + confirmed resubscription',
      );
      await eventually(
        () => chatHas(missed),
        reason: 'resync re-fetch recovers the missed message',
      );
      expect(subscriptionsTo('private-user.$buyerId'), subscribedBefore + 1);
      expect(chat.state.messages.where((m) => m.id == missed).length, 1);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('resume on a healthy connection resyncs without reconnecting', () async {
      final String threadPath = '/conversations/$sellerId/messages';
      final int before = counting.of(threadPath);
      final int connectsBefore = logs.where((l) => l.contains('socket connected')).length;

      realtime.resume();

      await eventually(
        () => counting.of(threadPath) > before,
        reason: 'resume → connected=true → silent re-fetch',
      );
      expect(logs.where((l) => l.contains('socket connected')).length, connectsBefore);
      expect(logs, contains('Realtime: connection healthy on resume; resynchronising.'));
    });

    test('an idle connection stays live across the heartbeat window', () async {
      await Future<void>.delayed(const Duration(seconds: 35));
      final int id = await sendMessage(sellerToken, buyerId, 'After idle');

      await eventually(() => chatHas(id), reason: 'still delivering after 35 s idle');
    }, timeout: const Timeout(Duration(minutes: 1)));
  });

  test('after an account switch no event of the previous account arrives', () async {
    realtime.stop();
    tokenStore.token = buyer2Token;
    connections.clear();
    await realtime.start(buyer2Id);
    await eventually(() => connections.contains(true), reason: 'buyer2 subscribed');
    events.clear();

    await sendMessage(sellerToken, buyerId, 'For the previous account');
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(events.where((e) => e.name == 'message.sent'), isEmpty);

    final int mine = await sendMessage(sellerToken, buyer2Id, 'For the current account');
    await eventually(
      () => events.any((e) => e.name == 'message.sent' && e.data['id'] == mine),
      reason: "the new account's own events arrive",
    );
    expect(subscriptionsTo('private-user.$buyer2Id'), 1);
  });

  test("subscribing to another user's channel is refused", () async {
    realtime.stop();
    // buyer2's token asking for the buyer's channel.
    connections.clear();
    await realtime.start(buyerId);

    await eventually(
      () => logs.any(
        (l) =>
            l.contains('Failed to subscribe to private-user.$buyerId') &&
            l.contains('(HTTP 403)'),
      ),
      reason: 'server refuses the subscription',
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(connections, isNot(contains(true)));
    expect(logs.any((l) => l.contains(buyer2Token)), isFalse, reason: 'token never logged');
    realtime.stop();
  });
}
