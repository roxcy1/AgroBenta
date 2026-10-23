import 'dart:convert';

import 'package:agrobenta_mobile/core/theme/app_colors.dart';
import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_controller.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_scope.dart';
import 'package:agrobenta_mobile/features/messaging/state/conversations_controller.dart';
import 'package:agrobenta_mobile/features/messaging/state/messaging_scope.dart';
import 'package:agrobenta_mobile/features/messaging/view/chat_screen.dart';
import 'package:agrobenta_mobile/features/messaging/view/conversations_screen.dart';
import 'package:agrobenta_mobile/features/messaging/widgets/conversation_tile.dart';
import 'package:agrobenta_mobile/features/notifications/state/notifications_controller.dart';
import 'package:agrobenta_mobile/features/notifications/state/notifications_scope.dart';
import 'package:agrobenta_mobile/features/notifications/view/notifications_screen.dart';
import 'package:agrobenta_mobile/repositories/messaging_repository.dart';
import 'package:agrobenta_mobile/repositories/notification_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/messaging_fakes.dart';
import '../../support/notification_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  setUp(() {
    tokenStore = FakeTokenStore('1|mobile-token');
    recorded = <RecordedRequest>[];
  });

  Future<void> settle(WidgetTester tester, {int frames = 12}) async {
    for (int frame = 0; frame < frames; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// A timestamp whose relative label is stable regardless of the machine's
  /// time zone: the same instant, a known duration in the past.
  String minutesAgo(int minutes) => DateTime.now()
      .toUtc()
      .subtract(Duration(minutes: minutes))
      .toIso8601String();

  /// Pumps the inbox exactly as the app does: the session-scoped controller
  /// and repository in [MessagingScope], the notifications stack the
  /// Notifications chip navigates into, an authenticated session in
  /// [AuthScope], and one transport answering the requests each makes.
  Future<void> pumpInbox(
    WidgetTester tester, {
    required Future<http.Response> Function(RecordedRequest request) handler,
  }) async {
    final MessagingRepository repository = buildMessagingRepository(
      tokenStore,
      handler,
      recorded: recorded,
    );
    final ConversationsController controller = ConversationsController(
      repository,
    );
    addTearDown(controller.dispose);

    final NotificationRepository notificationRepository =
        buildNotificationRepository(tokenStore, handler, recorded: recorded);
    final NotificationsController notificationsController =
        NotificationsController(notificationRepository);
    addTearDown(notificationsController.dispose);

    final AuthController authController = AuthController(
      buildAuthRepository(
        tokenStore,
        (_) async => http.Response(
          jsonEncode(successEnvelope(data: userJson(id: 7))),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(authController.dispose);
    tokenStore.token = 'stored-token';
    await authController.restoreSession();

    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MessagingScope(
        repository: repository,
        conversationsController: controller,
        child: NotificationsScope(
          repository: notificationRepository,
          controller: notificationsController,
          child: AuthScope(
            controller: authController,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const ConversationsScreen(),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Finder conversationTile(String name) => find.ancestor(
    of: find.text(name),
    matching: find.byType(ConversationTile),
  );

  group('renders', () {
    testWidgets('real conversations with previews, times and unread badges', (
      WidgetTester tester,
    ) async {
      await pumpInbox(
        tester,
        handler: (_) async => conversationsResponse(
          conversations: <Map<String, dynamic>>[
            conversationJson(
              counterpart: chatUserJson(id: 3, name: 'Rizal Farms'),
              listingTitle: 'Holstein Heifer',
              lastMessage: 'Still available?',
              lastMessageAt: minutesAgo(5),
              unreadCount: 2,
            ),
            conversationJson(
              counterpart: chatUserJson(id: 4, name: 'Ben Santos'),
              listingId: null,
              listingTitle: null,
              lastMessage: 'Thank you!',
              lastMessageAt: minutesAgo(3 * 24 * 60),
              unreadCount: 0,
            ),
          ],
        ),
      );

      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('Rizal Farms'), findsOneWidget);
      expect(find.text('Holstein Heifer'), findsOneWidget);
      expect(find.text('Still available?'), findsOneWidget);
      expect(find.text('5m'), findsOneWidget);
      expect(find.text('2'), findsOneWidget, reason: 'the unread count badge');

      expect(find.text('Ben Santos'), findsOneWidget);
      expect(
        find.text('Direct message'),
        findsOneWidget,
        reason: 'a thread with no listing says so rather than inventing one',
      );
      expect(find.text('3d'), findsOneWidget);
    });

    testWidgets('the empty-inbox state when the server returns nothing', (
      WidgetTester tester,
    ) async {
      await pumpInbox(tester, handler: (_) async => conversationsResponse());

      expect(find.text('No messages yet'), findsOneWidget);
      expect(
        find.text('Start a conversation from any listing.'),
        findsOneWidget,
      );
    });

    testWidgets('a load failure with a retry that actually reloads', (
      WidgetTester tester,
    ) async {
      int calls = 0;
      await pumpInbox(
        tester,
        handler: (RecordedRequest request) async {
          calls++;
          if (calls == 1) {
            return http.Response('{"message":"Server error."}', 500);
          }
          return conversationsResponse(
            conversations: <Map<String, dynamic>>[
              conversationJson(counterpart: chatUserJson(name: 'Rizal Farms')),
            ],
          );
        },
      );

      expect(find.text('Server error.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await settle(tester);

      expect(find.text('Rizal Farms'), findsOneWidget);
      expect(calls, 2);
    });
  });

  group('unread presentation', () {
    testWidgets('unread rows carry the pale-green surface, read rows do not', (
      WidgetTester tester,
    ) async {
      await pumpInbox(
        tester,
        handler: (_) async => conversationsResponse(
          conversations: <Map<String, dynamic>>[
            conversationJson(
              counterpart: chatUserJson(id: 3, name: 'Rizal Farms'),
              unreadCount: 1,
            ),
            conversationJson(
              counterpart: chatUserJson(id: 4, name: 'Ben Santos'),
              unreadCount: 0,
            ),
          ],
        ),
      );

      // A tile contains more than one Material (avatar, ink surface), so the
      // assertion checks the set of colours rather than a single widget.
      Iterable<Color?> materialColors(Finder tile) => tester
          .widgetList<Material>(
            find.descendant(of: tile, matching: find.byType(Material)),
          )
          .map((Material material) => material.color);

      expect(
        materialColors(conversationTile('Rizal Farms')),
        contains(AppColors.primarySurface),
      );
      expect(
        materialColors(conversationTile('Ben Santos')),
        isNot(contains(AppColors.primarySurface)),
      );
    });
  });

  group('search', () {
    testWidgets('narrows by participant name and the clear button restores', (
      WidgetTester tester,
    ) async {
      await pumpInbox(
        tester,
        handler: (_) async => conversationsResponse(
          conversations: <Map<String, dynamic>>[
            conversationJson(
              counterpart: chatUserJson(id: 3, name: 'Rizal Farms'),
            ),
            conversationJson(
              counterpart: chatUserJson(id: 4, name: 'Ben Santos'),
            ),
          ],
        ),
      );

      await tester.enterText(find.byType(TextField), 'rizal');
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Rizal Farms'), findsOneWidget);
      expect(find.text('Ben Santos'), findsNothing);

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Rizal Farms'), findsOneWidget);
      expect(find.text('Ben Santos'), findsOneWidget);
    });

    testWidgets('matches the listing title and the message preview', (
      WidgetTester tester,
    ) async {
      await pumpInbox(
        tester,
        handler: (_) async => conversationsResponse(
          conversations: <Map<String, dynamic>>[
            conversationJson(
              counterpart: chatUserJson(id: 3, name: 'Rizal Farms'),
              listingTitle: 'Holstein Heifer',
              lastMessage: 'Still available?',
            ),
            conversationJson(
              counterpart: chatUserJson(id: 4, name: 'Ben Santos'),
              listingId: null,
              listingTitle: null,
              lastMessage: 'See you Saturday',
            ),
          ],
        ),
      );

      await tester.enterText(find.byType(TextField), 'holstein');
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Rizal Farms'), findsOneWidget);
      expect(find.text('Ben Santos'), findsNothing);

      await tester.enterText(find.byType(TextField), 'saturday');
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Ben Santos'), findsOneWidget);
      expect(find.text('Rizal Farms'), findsNothing);
    });

    testWidgets('a no-results search shows its own state, not the empty '
        'inbox', (WidgetTester tester) async {
      await pumpInbox(
        tester,
        handler: (_) async => conversationsResponse(
          conversations: <Map<String, dynamic>>[
            conversationJson(counterpart: chatUserJson(name: 'Rizal Farms')),
          ],
        ),
      );

      await tester.enterText(find.byType(TextField), 'zzz-no-match');
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('No matching conversations'), findsOneWidget);
      expect(find.text('Try a different search or filter.'), findsOneWidget);
      // The empty-inbox copy must not appear — conversations do exist.
      expect(find.text('No messages yet'), findsNothing);
    });
  });

  group('category filters', () {
    testWidgets('Inquiries keeps only listing-scoped threads', (
      WidgetTester tester,
    ) async {
      await pumpInbox(
        tester,
        handler: (_) async => conversationsResponse(
          conversations: <Map<String, dynamic>>[
            conversationJson(
              counterpart: chatUserJson(id: 3, name: 'Rizal Farms'),
              listingId: 12,
            ),
            conversationJson(
              counterpart: chatUserJson(id: 4, name: 'Ben Santos'),
              listingId: null,
              listingTitle: null,
            ),
          ],
        ),
      );

      expect(find.text('Rizal Farms'), findsOneWidget);
      expect(find.text('Ben Santos'), findsOneWidget);

      await tester.tap(find.text('Inquiries'));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Rizal Farms'), findsOneWidget);
      expect(find.text('Ben Santos'), findsNothing);

      await tester.tap(find.text('All'));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Rizal Farms'), findsOneWidget);
      expect(find.text('Ben Santos'), findsOneWidget);
    });

    testWidgets('Transactions is disabled and Notifications opens its own '
        'destination', (WidgetTester tester) async {
      await pumpInbox(tester, handler: (_) async => conversationsResponse());

      final Finder transactions = find.ancestor(
        of: find.text('Transactions'),
        matching: find.byType(InkWell),
      );
      expect(transactions, findsOneWidget, reason: 'Transactions is shown');
      expect(
        tester.widget<InkWell>(transactions).onTap,
        isNull,
        reason: 'no data model supports a transaction-message link (GAP-11)',
      );

      final Finder notifications = find.ancestor(
        of: find.text('Notifications'),
        matching: find.byType(InkWell),
      );
      expect(notifications, findsOneWidget);
      expect(
        tester.widget<InkWell>(notifications).onTap,
        isNotNull,
        reason: 'notifications have a real, separate destination',
      );

      await tester.tap(find.text('Notifications'));
      await settle(tester);

      // The chip is a shortcut, not a filter: it leaves the inbox for the
      // existing notifications screen. Whether that screen fetches is its own
      // feature's concern (and its own test), not this chip's.
      expect(find.byType(NotificationsScreen), findsOneWidget);
    });
  });

  group('opening a conversation', () {
    testWidgets('marks the thread read and pushes the chat screen', (
      WidgetTester tester,
    ) async {
      await pumpInbox(
        tester,
        handler: (RecordedRequest request) async {
          if (request.method == 'POST') {
            return threadReadResponse(updated: 2);
          }
          return conversationsResponse(
            conversations: <Map<String, dynamic>>[
              conversationJson(
                counterpart: chatUserJson(id: 3, name: 'Rizal Farms'),
                unreadCount: 2,
              ),
            ],
          );
        },
      );

      await tester.tap(find.text('Rizal Farms'));
      await settle(tester);

      // The chat screen is open for the right counterpart.
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text('Rizal Farms'), findsWidgets);

      // The thread was marked read through the supported endpoint — twice by
      // design: the inbox clears its badge optimistically and the chat screen
      // marks the thread read again on open. Both hit the same route.
      final List<RecordedRequest> posts = recorded
          .where((RecordedRequest r) => r.method == 'POST')
          .toList(growable: false);
      expect(posts, hasLength(2));
      expect(
        posts.map((RecordedRequest r) => r.apiPath).toList(),
        everyElement('/conversations/3/read'),
      );
    });

    testWidgets('a failed mark-read never breaks navigation', (
      WidgetTester tester,
    ) async {
      await pumpInbox(
        tester,
        handler: (RecordedRequest request) async {
          if (request.method == 'POST') {
            return http.Response('{"message":"Server error."}', 500);
          }
          return conversationsResponse(
            conversations: <Map<String, dynamic>>[
              conversationJson(
                counterpart: chatUserJson(id: 3, name: 'Rizal Farms'),
                unreadCount: 2,
              ),
            ],
          );
        },
      );

      await tester.tap(find.text('Rizal Farms'));
      await settle(tester);

      expect(find.byType(ChatScreen), findsOneWidget);
    });
  });
}
