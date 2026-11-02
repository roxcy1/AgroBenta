import 'dart:async';
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
import 'package:agrobenta_mobile/features/inquiries/state/inquiry_scope.dart';
import 'package:agrobenta_mobile/features/offers/state/offer_scope.dart';
import 'package:agrobenta_mobile/features/transactions/state/transaction_scope.dart';
import 'package:agrobenta_mobile/repositories/inquiry_repository.dart';
import 'package:agrobenta_mobile/repositories/messaging_repository.dart';
import 'package:agrobenta_mobile/repositories/offer_repository.dart';
import 'package:agrobenta_mobile/repositories/transaction_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/inquiry_fakes.dart';
import '../../support/messaging_fakes.dart';
import '../../support/offer_fakes.dart';
import '../../support/transaction_fakes.dart';

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
  /// and repository in [MessagingScope], an authenticated session in
  /// [AuthScope], and one transport answering the requests each makes.
  /// [sellerMode] mirrors the Account Mode the shell passes down.
  Future<void> pumpInbox(
    WidgetTester tester, {
    required Future<http.Response> Function(RecordedRequest request) handler,
    bool sellerMode = false,
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

    // The chat screen reads this scope for its offer panel. These inbox tests
    // never open an offer, so an empty list is the honest answer.
    final OfferRepository offerRepository = buildOfferRepository(
      tokenStore,
      (_) async => offersResponse(offers: <Map<String, dynamic>>[]),
      recorded: recorded,
    );

    final InquiryRepository inquiryRepository = buildInquiryRepository(
      tokenStore,
      handler,
      recorded: recorded,
    );
    final TransactionRepository transactionRepository =
        buildTransactionRepository(tokenStore, handler, recorded: recorded);

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
        child: OfferScope(
          repository: offerRepository,
          child: InquiryScope(
            repository: inquiryRepository,
            child: TransactionScope(
              repository: transactionRepository,
              child: AuthScope(
                controller: authController,
                child: MaterialApp(
                  theme: AppTheme.light(),
                  home: ConversationsScreen(sellerMode: sellerMode),
                ),
              ),
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

      expect(find.text('Something went wrong on the server.'), findsOneWidget);
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

  group('category tabs', () {
    Future<http.Response> tabsHandler(RecordedRequest request) async {
      if (request.apiPath == '/inquiries') {
        return inquiryListResponse(
          inquiries: <Map<String, dynamic>>[
            inquiryListItemJson(
              counterpartName: 'Pedro Reyes',
              listingTitle: 'cattle Angus',
              latestOffer: inquiryListOfferJson(status: 'pending'),
            ),
            inquiryListItemJson(
              id: 56,
              counterpartName: 'Ana Cruz',
              listingTitle: 'goat Boer',
              latestOffer: inquiryListOfferJson(
                id: 42,
                status: 'declined',
                proposedAmount: '18000.00',
              ),
            ),
          ],
        );
      }

      if (request.apiPath == '/transactions') {
        return transactionListResponse(
          transactions: <Map<String, dynamic>>[
            transactionJson(
              listing: transactionListingJson(
                livestockType: 'cattle',
                breed: 'Angus',
              ),
              totalAmount: '47000.00',
            ),
          ],
          total: 1,
        );
      }

      return conversationsResponse();
    }

    testWidgets('Inquiries lists individual active inquiries for the buyer', (
      WidgetTester tester,
    ) async {
      await pumpInbox(tester, handler: tabsHandler);

      await tester.tap(find.text('Inquiries'));
      await tester.pumpAndSettle();

      final RecordedRequest inquiryRequest = recorded.firstWhere(
        (RecordedRequest r) => r.apiPath == '/inquiries',
      );
      expect(inquiryRequest.query['role'], 'buyer');

      expect(find.text('Pedro Reyes'), findsOneWidget);
      expect(find.textContaining('cattle Angus'), findsOneWidget);
      expect(
        find.text('Needs your decision'),
        findsOneWidget,
        reason: 'a pending offer needs the buyer',
      );
      expect(find.text('You are the buyer'), findsWidgets);
      expect(find.text('Offer declined'), findsOneWidget);
    });

    testWidgets('the seller tab shows their own side, not a buyer decision', (
      WidgetTester tester,
    ) async {
      await pumpInbox(
        tester,
        sellerMode: true,
        handler: (RecordedRequest request) async {
          if (request.apiPath == '/inquiries') {
            return inquiryListResponse(
              inquiries: <Map<String, dynamic>>[
                inquiryListItemJson(
                  role: 'seller',
                  counterpartName: 'Pedro Reyes',
                  listingTitle: 'cattle Angus',
                  latestOffer: inquiryListOfferJson(status: 'pending'),
                  canMakeOffer: false,
                ),
              ],
            );
          }
          return conversationsResponse();
        },
      );

      await tester.tap(find.text('Inquiries'));
      await tester.pumpAndSettle();

      final RecordedRequest inquiryRequest = recorded.firstWhere(
        (RecordedRequest r) => r.apiPath == '/inquiries',
      );
      expect(inquiryRequest.query['role'], 'seller');

      expect(find.text('Offer pending'), findsOneWidget);
      expect(find.text('Needs your decision'), findsNothing);
      expect(find.text('You are the seller'), findsOneWidget);
    });

    testWidgets('Transactions shows read-only records with detail and chat', (
      WidgetTester tester,
    ) async {
      await pumpInbox(tester, handler: tabsHandler);

      await tester.tap(find.text('Transactions'));
      await tester.pumpAndSettle();

      expect(find.textContaining('47,000'), findsOneWidget);
      expect(find.text('Open chat'), findsOneWidget);

      await tester.tap(find.text('Open chat'));
      await tester.pumpAndSettle();

      expect(find.byType(ChatScreen), findsOneWidget);
    });

    testWidgets('a delayed response ends in the ready state, not a spinner', (
      WidgetTester tester,
    ) async {
      final Completer<http.Response> pending = Completer<http.Response>();

      await pumpInbox(
        tester,
        handler: (RecordedRequest request) async {
          if (request.apiPath == '/inquiries') {
            return pending.future;
          }
          return conversationsResponse();
        },
      );

      await tester.tap(find.text('Inquiries'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      pending.complete(
        inquiryListResponse(
          inquiries: <Map<String, dynamic>>[
            inquiryListItemJson(counterpartName: 'Pedro Reyes'),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Pedro Reyes'), findsOneWidget);
    });

    testWidgets('a delayed transactions response also leaves the spinner', (
      WidgetTester tester,
    ) async {
      final Completer<http.Response> pending = Completer<http.Response>();

      await pumpInbox(
        tester,
        handler: (RecordedRequest request) async {
          if (request.apiPath == '/transactions') {
            return pending.future;
          }
          return conversationsResponse();
        },
      );

      await tester.tap(find.text('Transactions'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      pending.complete(
        transactionListResponse(
          transactions: <Map<String, dynamic>>[transactionJson()],
          total: 1,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Open chat'), findsOneWidget);
    });

    testWidgets('empty inquiries end in the empty state, not a spinner', (
      WidgetTester tester,
    ) async {
      await pumpInbox(
        tester,
        handler: (RecordedRequest request) async {
          if (request.apiPath == '/inquiries') {
            return inquiryListResponse();
          }
          return conversationsResponse();
        },
      );

      await tester.tap(find.text('Inquiries'));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('No active inquiries'), findsOneWidget);
      expect(
        recorded.where((RecordedRequest r) => r.apiPath == '/inquiries'),
        hasLength(1),
        reason: 'rebuilds must not re-request the tab',
      );
    });

    testWidgets('empty transactions end in the empty state, not a spinner', (
      WidgetTester tester,
    ) async {
      await pumpInbox(
        tester,
        handler: (RecordedRequest request) async {
          if (request.apiPath == '/transactions') {
            return transactionListResponse(
              transactions: <Map<String, dynamic>>[],
              total: 0,
            );
          }
          return conversationsResponse();
        },
      );

      await tester.tap(find.text('Transactions'));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('No transactions yet'), findsOneWidget);
      expect(
        recorded.where((RecordedRequest r) => r.apiPath == '/transactions'),
        hasLength(1),
        reason: 'rebuilds must not re-request the tab',
      );
    });

    testWidgets('opening an inquiry tile starts its chat', (
      WidgetTester tester,
    ) async {
      await pumpInbox(tester, handler: tabsHandler);

      await tester.tap(find.text('Inquiries'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pedro Reyes'));
      await tester.pumpAndSettle();

      expect(find.byType(ChatScreen), findsOneWidget);
    });

    testWidgets('Notifications is no longer a Messages filter', (
      WidgetTester tester,
    ) async {
      await pumpInbox(tester, handler: (_) async => conversationsResponse());

      // The chip was a shortcut, not a category. It now lives only on Home's
      // bell, so Messages keeps All, Inquiries and Transactions.
      expect(find.text('Notifications'), findsNothing);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Inquiries'), findsOneWidget);
      expect(find.text('Transactions'), findsOneWidget);
    });
  });

  group('account mode', () {
    List<Map<String, dynamic>> threads() => <Map<String, dynamic>>[
      conversationJson(
        counterpart: chatUserJson(id: 3, name: 'Buyer Thread'),
        roles: const <String>['buyer'],
      ),
      conversationJson(
        counterpart: chatUserJson(id: 4, name: 'Seller Thread'),
        roles: const <String>['seller'],
      ),
      conversationJson(
        counterpart: chatUserJson(id: 5, name: 'Both Thread'),
        roles: const <String>['buyer', 'seller'],
      ),
      conversationJson(
        counterpart: chatUserJson(id: 6, name: 'Legacy Thread'),
        roles: const <String>[],
      ),
    ];

    testWidgets('Buyer Mode hides seller-only threads', (
      WidgetTester tester,
    ) async {
      await pumpInbox(
        tester,
        handler: (_) async =>
            conversationsResponse(conversations: threads()),
      );

      expect(find.text('Buyer Thread'), findsOneWidget);
      expect(find.text('Both Thread'), findsOneWidget);
      expect(
        find.text('Legacy Thread'),
        findsOneWidget,
        reason: 'an unclassifiable thread is never hidden',
      );
      expect(find.text('Seller Thread'), findsNothing);
    });

    testWidgets('Seller Mode hides buyer-only threads', (
      WidgetTester tester,
    ) async {
      await pumpInbox(
        tester,
        sellerMode: true,
        handler: (_) async =>
            conversationsResponse(conversations: threads()),
      );

      expect(find.text('Seller Thread'), findsOneWidget);
      expect(find.text('Both Thread'), findsOneWidget);
      expect(find.text('Legacy Thread'), findsOneWidget);
      expect(find.text('Buyer Thread'), findsNothing);
    });
  });

  group('previews', () {
    testWidgets('listing, multi-listing context and offer status', (
      WidgetTester tester,
    ) async {
      await pumpInbox(
        tester,
        handler: (_) async => conversationsResponse(
          conversations: <Map<String, dynamic>>[
            conversationJson(
              counterpart: chatUserJson(id: 3, name: 'Rizal Farms'),
              listingTitle: 'Holstein Heifer',
              listingPrice: '50000.00',
              listingCount: 3,
              latestOffer: conversationOfferJson(status: 'pending'),
            ),
            conversationJson(
              counterpart: chatUserJson(id: 4, name: 'Ben Santos'),
              listingTitle: 'Boer Goat',
              hasInquiry: true,
            ),
          ],
        ),
      );

      expect(
        find.textContaining('Holstein Heifer'),
        findsOneWidget,
        reason: 'the preview names the listing',
      );
      expect(
        find.textContaining('+2 more listings'),
        findsOneWidget,
        reason: 'the other two listings are counted, not hidden',
      );
      expect(
        find.textContaining('50,000'),
        findsOneWidget,
        reason: 'the listed price is shown without opening the chat',
      );
      expect(find.text('Offer pending'), findsOneWidget);
      expect(find.text('Boer Goat'), findsOneWidget);
      expect(find.text('Inquiry'), findsOneWidget);
    });
  });

  group('opening a conversation', () {
    testWidgets('entering Messages never marks a thread read', (
      WidgetTester tester,
    ) async {
      await pumpInbox(
        tester,
        handler: (_) async => conversationsResponse(
          conversations: <Map<String, dynamic>>[
            conversationJson(
              counterpart: chatUserJson(id: 3, name: 'Rizal Farms'),
              unreadCount: 2,
            ),
          ],
        ),
      );

      expect(find.text('Rizal Farms'), findsOneWidget);
      expect(
        recorded.where((RecordedRequest r) => r.method == 'POST'),
        isEmpty,
        reason: 'reading happens when a conversation is opened, not on arrival',
      );
    });

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

    testWidgets('Seller Mode passes the eligible inquiry into the chat', (
      WidgetTester tester,
    ) async {
      await pumpInbox(
        tester,
        sellerMode: true,
        handler: (RecordedRequest request) async {
          if (request.apiPath.startsWith('/offers')) {
            return offersResponse(offers: <Map<String, dynamic>>[]);
          }
          if (request.method == 'POST') {
            return threadReadResponse();
          }
          return conversationsResponse(
            conversations: <Map<String, dynamic>>[
              conversationJson(
                counterpart: chatUserJson(id: 3, name: 'Rizal Farms'),
                roles: const <String>['seller'],
                eligibleInquiry: eligibleInquiryJson(),
              ),
            ],
          );
        },
      );

      await tester.tap(find.text('Rizal Farms'));
      await settle(tester);

      expect(find.byType(ChatScreen), findsOneWidget);
      expect(
        find.text('Make an Offer'),
        findsOneWidget,
        reason: 'the server supplied an eligible inquiry for this seller',
      );
      expect(
        find.text('Buyer'),
        findsOneWidget,
        reason: 'the header names the counterpart role from the conversation',
      );

      // The header opens the compact public-profile panel.
      await tester.tap(find.text('Rizal Farms').first);
      await settle(tester);
      expect(
        find.textContaining('Only the profile details'),
        findsOneWidget,
      );
    });

    testWidgets('Buyer Mode never offers the seller action', (
      WidgetTester tester,
    ) async {
      await pumpInbox(
        tester,
        handler: (RecordedRequest request) async {
          if (request.apiPath.startsWith('/offers')) {
            return offersResponse(offers: <Map<String, dynamic>>[]);
          }
          if (request.method == 'POST') {
            return threadReadResponse();
          }
          return conversationsResponse(
            conversations: <Map<String, dynamic>>[
              conversationJson(
                counterpart: chatUserJson(id: 3, name: 'Rizal Farms'),
                // The caller sells to this counterpart too, but this inbox is
                // Buyer Mode, so the buyer experience is what is shown.
                roles: const <String>['buyer', 'seller'],
                eligibleInquiry: eligibleInquiryJson(),
              ),
            ],
          );
        },
      );

      await tester.tap(find.text('Rizal Farms'));
      await settle(tester);

      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text('Make an Offer'), findsNothing);
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
