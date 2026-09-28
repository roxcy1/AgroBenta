import 'dart:convert';

import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_controller.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_scope.dart';
import 'package:agrobenta_mobile/features/buyer_shell/view/buyer_shell.dart';
import 'package:agrobenta_mobile/features/home/view/buyer_home_screen.dart';
import 'package:agrobenta_mobile/features/marketplace/state/marketplace_controller.dart';
import 'package:agrobenta_mobile/features/marketplace/state/marketplace_scope.dart';
import 'package:agrobenta_mobile/features/marketplace/views/marketplace_screen.dart';
import 'package:agrobenta_mobile/features/marketplace/widgets/listing_card.dart';
import 'package:agrobenta_mobile/repositories/marketplace_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/marketplace_fakes.dart';
import '../../support/marketplace_app_harness.dart';
import '../../support/seller_verification_app_harness.dart';

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  setUp(() {
    tokenStore = FakeTokenStore('token');
    recorded = <RecordedRequest>[];
  });

  /// Pumps the shell over a mock marketplace transport.
  Future<MarketplaceController> pumpShell(
    WidgetTester tester, {
    Future<http.Response> Function(RecordedRequest request)? handler,
  }) async {
    final MarketplaceRepository repository = buildMarketplaceRepository(
      tokenStore,
      handler ?? (_) async => marketplaceListResponse(),
      recorded: recorded,
    );
    final MarketplaceController controller = MarketplaceController(repository);
    addTearDown(controller.dispose);

    // The home tab reads the session, so the shell needs an `AuthScope` too —
    // the same pair of scopes `main.dart` installs, in the same arrangement.
    final AuthController authController = AuthController(
      buildAuthRepository(
        tokenStore,
        (_) async => http.Response(
          jsonEncode(successEnvelope(data: userJson())),
          200,
        ),
      ),
    );
    addTearDown(authController.dispose);
    tokenStore.token = 'stored-token';
    await authController.restoreSession();

    await tester.pumpWidget(
      // Scopes above `MaterialApp`, matching `main.dart`: a route pushed onto
      // the navigator is a sibling of `home`, so a scope inside `home` would
      // not be visible to it.
      AuthScope(
        controller: authController,
        child: MarketplaceScope(
          repository: repository,
          controller: controller,
          // The Home tab's seller card reads the seller verification scope, so
          // the shell harness carries all three scopes `main.dart` installs.
          // Answered with "never submitted" — this test is about navigation, and
          // the card must not need a transport to render.
          child: NeverSubmittedVerificationScope(
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const BuyerShell(),
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
      bar.destinations
          .cast<Widget>()
          .whereType<NavigationDestination>()
          .map((NavigationDestination d) => d.label),
      <String>['Home', 'Marketplace'],
    );
  });

  testWidgets('adds no placeholder destinations for later phases', (
    WidgetTester tester,
    ) async {
    await pumpShell(tester);

    // Transactions, Notifications and Profile are M3+. A disabled or "coming
    // soon" tab advertises a screen that cannot be opened.
    expect(find.text('Transactions'), findsNothing);
    expect(find.text('Notifications'), findsNothing);
    expect(find.text('Profile'), findsNothing);
  });

  testWidgets('starts on Home', (WidgetTester tester) async {
    await pumpShell(tester);

    expect(find.byType(BuyerHomeScreen), findsOneWidget);
    expect(find.text('Browse the marketplace'), findsOneWidget);
  });

  testWidgets('switches to the marketplace tab', (WidgetTester tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('Marketplace'));
    await settleMarketplace(tester, frames: 12);

    expect(find.byType(MarketplaceScreen), findsOneWidget);
    expect(find.text('Marketplace'), findsWidgets);
  });

  testWidgets('the home card navigates to the marketplace tab', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);

    // The default 800x600 test surface puts this button at the very bottom,
    // overlapping the navigation bar, so scroll it into view before tapping —
    // otherwise the tap lands on the bar instead of the button and the test
    // would pass for the wrong reason.
    await tester.ensureVisible(find.text('Go to marketplace'));
    await settleMarketplace(tester);
    await tester.tap(find.text('Go to marketplace'));
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

    await tester.tap(find.text('Marketplace'));
    await settleMarketplace(tester, frames: 12);
    expect(find.text('Kept'), findsOneWidget);
    expect(listCalls, 1);

    await tester.tap(find.text('Home'));
    await settleMarketplace(tester, frames: 12);

    await tester.tap(find.text('Marketplace'));
    await settleMarketplace(tester, frames: 12);

    expect(
      listCalls,
      1,
      reason: 'the shell keeps both tabs alive, so returning must not re-fetch '
          'page 1 and throw away what the buyer had',
    );
    expect(find.text('Kept'), findsOneWidget);
  });
}
