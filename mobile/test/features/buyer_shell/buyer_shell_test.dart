import 'dart:convert';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/account_mode/state/account_mode_controller.dart';
import 'package:agrobenta_mobile/features/account_mode/state/account_mode_scope.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_controller.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_scope.dart';
import 'package:agrobenta_mobile/features/buyer_shell/view/buyer_shell.dart';
import 'package:agrobenta_mobile/features/home/view/buyer_home_screen.dart';
import 'package:agrobenta_mobile/features/marketplace/state/marketplace_controller.dart';
import 'package:agrobenta_mobile/features/marketplace/state/marketplace_scope.dart';
import 'package:agrobenta_mobile/features/marketplace/views/marketplace_screen.dart';
import 'package:agrobenta_mobile/features/marketplace/widgets/listing_card.dart';
import 'package:agrobenta_mobile/features/messaging/state/conversations_controller.dart';
import 'package:agrobenta_mobile/features/messaging/state/messaging_scope.dart';
import 'package:agrobenta_mobile/features/notifications/state/notifications_controller.dart';
import 'package:agrobenta_mobile/features/notifications/state/notifications_scope.dart';
import 'package:agrobenta_mobile/features/profile/state/profile_controller.dart';
import 'package:agrobenta_mobile/features/profile/state/profile_scope.dart';
import 'package:agrobenta_mobile/features/transactions/state/transaction_scope.dart';
import 'package:agrobenta_mobile/features/transactions/views/transactions_screen.dart';
import 'package:agrobenta_mobile/repositories/marketplace_repository.dart';
import 'package:agrobenta_mobile/repositories/messaging_repository.dart';
import 'package:agrobenta_mobile/repositories/notification_repository.dart';
import 'package:agrobenta_mobile/repositories/profile_repository.dart';
import 'package:agrobenta_mobile/repositories/transaction_repository.dart';
import 'package:agrobenta_mobile/services/messaging_service.dart';
import 'package:agrobenta_mobile/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/auth_fakes.dart';
import '../../support/marketplace_fakes.dart';
import '../../support/marketplace_app_harness.dart';
import '../../support/messaging_fakes.dart';
import '../../support/notification_fakes.dart';
import '../../support/seller_verification_app_harness.dart';
import '../../support/transaction_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  setUp(() {
    tokenStore = FakeTokenStore('token');
    recorded = <RecordedRequest>[];
  });

  /// A `GET /profile` response — the `UserResource` the profile screen loads
  /// from its `initState`.
  http.Response profileResponse() => http.Response(
    jsonEncode(successEnvelope(data: userJson())),
    200,
    headers: <String, String>{'content-type': 'application/json'},
  );

  /// Pumps the shell over a mock transport.
  Future<MarketplaceController> pumpShell(
    WidgetTester tester, {
    Future<http.Response> Function(RecordedRequest request)? handler,
  }) async {
    // One transport answers for the shell's data-holding screens: the
    // marketplace keeps its configurable handler, while the transactions tab
    // and the profile screen — both of which the shell builds eagerly in its
    // `IndexedStack` — get their own canonical fixtures. They must answer
    // successfully, because the scopes `main.dart` installs sit above the
    // shell and their screens load on mount.
    Future<http.Response> transport(RecordedRequest request) {
      switch (request.apiPath) {
        case '/transactions':
          return Future<http.Response>.value(transactionListResponse());
        case '/profile':
          return Future<http.Response>.value(profileResponse());
        case '/conversations':
          // The Messages tab loads its inbox on mount, exactly as in the app.
          return Future<http.Response>.value(conversationsResponse());
        case '/notifications/unread-count':
          // Home's bell refreshes the live badge from `initState`.
          return Future<http.Response>.value(unreadCountResponse());
        case '/notifications':
          return Future<http.Response>.value(notificationsPageResponse());
        default:
          return handler != null
              ? handler(request)
              : Future<http.Response>.value(marketplaceListResponse());
      }
    }

    final MarketplaceRepository repository = buildMarketplaceRepository(
      tokenStore,
      transport,
      recorded: recorded,
    );
    final MarketplaceController controller = MarketplaceController(repository);
    addTearDown(controller.dispose);

    // The home tab reads the session, so the shell needs an `AuthScope` too —
    // the same pair of scopes `main.dart` installs, in the same arrangement.
    final AuthController authController = AuthController(
      buildAuthRepository(
        tokenStore,
        (_) async =>
            http.Response(jsonEncode(successEnvelope(data: userJson())), 200),
      ),
    );
    addTearDown(authController.dispose);

    final AccountModeController accountModeController = AccountModeController(
      authController,
    );
    addTearDown(accountModeController.dispose);

    tokenStore.token = 'stored-token';
    await authController.restoreSession();

    // Profile and transactions each load from their screen's `initState`, so
    // their scopes — and their controllers — are part of the shell's real
    // environment, exactly as `main.dart` installs them above `MaterialApp`.
    final ProfileRepository profileRepository = ProfileRepository(
      ProfileService(
        ApiClient(
          tokenStorage: tokenStore,
          httpClient: MockClient(
            (http.Request request) => transport(RecordedRequest(request)),
          ),
        ),
      ),
    );
    final ProfileController profileController = ProfileController(
      profileRepository,
    );
    addTearDown(profileController.dispose);

    final TransactionRepository transactionRepository =
        buildTransactionRepository(tokenStore, transport);

    // The shell reads the session-scoped ConversationsController for the
    // Messages tab badge, and its IndexedStack builds the Conversations
    // screen eagerly — so the messaging scope is part of the shell's real
    // environment, exactly as `main.dart` installs it.
    final MessagingRepository messagingRepository = MessagingRepository(
      MessagingService(
        ApiClient(
          tokenStorage: tokenStore,
          httpClient: MockClient(
            (http.Request request) => transport(RecordedRequest(request)),
          ),
        ),
      ),
    );
    final ConversationsController conversationsController =
        ConversationsController(messagingRepository);
    addTearDown(conversationsController.dispose);

    // Home's AppBar bell and the Notifications screen share one
    // session-scoped controller — the shell harness carries the same scope
    // `main.dart` installs.
    final NotificationRepository notificationRepository =
        buildNotificationRepository(tokenStore, transport);
    final NotificationsController notificationsController =
        NotificationsController(notificationRepository);
    addTearDown(notificationsController.dispose);

    await tester.pumpWidget(
      // Scopes above `MaterialApp`, matching `main.dart`: a route pushed onto
      // the navigator is a sibling of `home`, so a scope inside `home` would
      // not be visible to it.
      MessagingScope(
        repository: messagingRepository,
        conversationsController: conversationsController,
        child: NotificationsScope(
          repository: notificationRepository,
          controller: notificationsController,
          child: AuthScope(
            controller: authController,
            child: AccountModeScope(
              controller: accountModeController,
              child: MarketplaceScope(
                repository: repository,
                controller: controller,
                // The Home tab's seller card reads the seller verification scope, so
                // the shell harness carries the scopes `main.dart` installs.
                // Answered with "never submitted" — this test is about navigation, and
                // the card must not need a transport to render.
                child: NeverSubmittedVerificationScope(
                  child: ProfileScope(
                    repository: profileRepository,
                    controller: profileController,
                    child: TransactionScope(
                      repository: transactionRepository,
                      child: MaterialApp(
                        theme: AppTheme.light(),
                        home: const BuyerShell(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settleMarketplace(tester);

    return controller;
  }

  testWidgets('offers exactly the destinations that exist', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);

    final NavigationBar bar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );

    expect(
      bar.destinations.cast<Widget>().whereType<NavigationDestination>().map(
        (NavigationDestination d) => d.label,
      ),
      <String>['Home', 'Browse', 'Messages', 'Transactions', 'Profile'],
    );
  });

  testWidgets('adds no placeholder destinations for later phases', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);

    // Notifications is still a later phase. A disabled or "coming soon"
    // destination advertises a screen that cannot be opened — the four
    // labels above are exactly the screens that exist, each of them real.
    expect(find.text('Notifications'), findsNothing);
  });

  testWidgets('starts on Home', (WidgetTester tester) async {
    await pumpShell(tester);

    expect(find.byType(BuyerHomeScreen), findsOneWidget);
    expect(
      find.text('Quality Livestock for a Better Tomorrow'),
      findsOneWidget,
    );
  });

  testWidgets('switches to the browse tab', (WidgetTester tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('Browse'));
    await settleMarketplace(tester, frames: 12);

    expect(find.byType(MarketplaceScreen), findsOneWidget);
    expect(find.text('Marketplace'), findsWidgets);
  });

  testWidgets('switches to the transactions tab', (WidgetTester tester) async {
    await pumpShell(tester);

    // Tapped inside the bar: the screen's own `AppBar` also says
    // "Transactions" once the tab is selected, and the bar is the control
    // under test.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Transactions'),
      ),
    );
    await settleMarketplace(tester, frames: 12);

    expect(find.byType(TransactionsScreen), findsOneWidget);
    expect(
      find.text('TRX-001'),
      findsOneWidget,
      reason: 'the freshly loaded pending tab shows its record',
    );
  });

  testWidgets('the home card navigates to the marketplace tab', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);

    // The hero CTA leads into the marketplace. On the default 800x600 test
    // surface it may sit at the edge of the viewport, so scroll it into view
    // before tapping — otherwise the tap could land on the navigation bar
    // instead of the button and the test would pass for the wrong reason.
    await tester.ensureVisible(find.text('Explore Now'));
    await settleMarketplace(tester);
    await tester.tap(find.text('Explore Now'));
    await settleMarketplace(tester, frames: 12);

    expect(find.byType(ListingCard), findsOneWidget);
  });

  testWidgets('keeps the loaded list when switching away and back', (
    WidgetTester tester,
  ) async {
    int listCalls = 0;
    await pumpShell(
      tester,
      handler: (RecordedRequest request) async {
        if (request.apiPath != '/listings') {
          return listingDetailResponse();
        }
        listCalls++;
        return marketplaceListResponse(
          listings: <Map<String, dynamic>>[listingJson(breed: 'Kept')],
        );
      },
    );

    await tester.tap(find.text('Browse'));
    await settleMarketplace(tester, frames: 12);
    expect(find.text('Kept'), findsOneWidget);
    expect(listCalls, 1);

    await tester.tap(find.text('Home'));
    await settleMarketplace(tester, frames: 12);

    await tester.tap(find.text('Browse'));
    await settleMarketplace(tester, frames: 12);

    expect(
      listCalls,
      1,
      reason:
          'the shell keeps both tabs alive, so returning must not re-fetch '
          'page 1 and throw away what the buyer had',
    );
    expect(find.text('Kept'), findsOneWidget);
  });
}
