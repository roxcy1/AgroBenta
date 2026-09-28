import 'dart:convert';

import 'package:agrobenta_mobile/features/auth/state/auth_controller.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_scope.dart';
import 'package:agrobenta_mobile/features/home/view/buyer_home_screen.dart';
import 'package:agrobenta_mobile/features/seller_verification/state/seller_verification_controller.dart';
import 'package:agrobenta_mobile/features/seller_verification/state/seller_verification_scope.dart';
import 'package:agrobenta_mobile/features/seller_verification/view/seller_verification_screen.dart';
import 'package:agrobenta_mobile/models/user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_app_harness.dart';
import '../../support/auth_fakes.dart';
import '../../support/seller_verification_app_harness.dart';
import '../../support/seller_verification_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;

  setUp(() => tokenStore = FakeTokenStore());

  /// Pumps the home screen with an already-restored session, which is the only
  /// way the gate would ever show it.
  ///
  /// [verification] is what `/seller-verification/me` answers; `null` is a 404,
  /// which is the normal "never applied" state.
  Future<AuthController> pumpSignedIn(
    WidgetTester tester, {
    Map<String, dynamic>? user,
    Map<String, dynamic>? verification,
  }) async {
    final AuthController controller = AuthController(
      buildAuthRepository(
        tokenStore,
        (_) async => http.Response(
          jsonEncode(successEnvelope(data: user ?? userJson())),
          200,
        ),
      ),
    );
    addTearDown(controller.dispose);

    final SellerVerificationController verificationController =
        buildSellerVerificationController(
          tokenStore,
          (_) async =>
              verification == null
                  ? sellerVerificationNotFoundResponse()
                  : sellerVerificationResponse(verification: verification),
        );
    addTearDown(verificationController.dispose);

    tokenStore.token = 'stored-token';
    await controller.restoreSession();

    await tester.pumpWidget(
      // Scopes **above** `MaterialApp`, as `main.dart` does. A route pushed onto
      // the navigator is a sibling of `home` inside the overlay, so a scope
      // nested in `home` would be invisible to the pushed verification screen —
      // which is the arrangement this test is in a position to catch.
      AuthScope(
        controller: controller,
        child: SellerVerificationScope(
          repository: buildSellerVerificationRepository(
            tokenStore,
            (_) async => sellerVerificationNotFoundResponse(),
          ),
          controller: verificationController,
          child: const MaterialApp(home: BuyerHomeScreen()),
        ),
      ),
    );
    await settleAuth(tester, frames: 12);

    return controller;
  }

  testWidgets('greets the user and shows the account', (
    WidgetTester tester,
  ) async {
    await pumpSignedIn(tester);

    expect(find.text('Welcome, Ana Reyes'), findsOneWidget);
    expect(find.text('ana@example.test'), findsOneWidget);
  });

  testWidgets('shows a new account as a Buyer', (WidgetTester tester) async {
    await pumpSignedIn(tester);

    expect(find.text('Buyer'), findsOneWidget);
    expect(find.text('Seller'), findsNothing);
  });

  testWidgets('reflects a server-granted seller capability', (
    WidgetTester tester,
  ) async {
    await pumpSignedIn(
      tester,
      user: userJson(sellerCapability: 'seller'),
    );

    expect(find.text('Seller'), findsOneWidget);
  });

  testWidgets('invents no listings', (WidgetTester tester) async {
    await pumpSignedIn(tester);

    // The marketplace is real now, but it lives behind its own tab and is
    // covered by its own tests. What must not happen is this screen inventing
    // listing-shaped records to fill itself.
    expect(find.text('No active listings yet'), findsNothing);
    expect(find.textContaining('later releases'), findsNothing);
    expect(find.byType(ListView), findsNothing);
  });

  group('seller verification card', () {
    testWidgets('offers to become a seller when nothing is on file', (
      WidgetTester tester,
    ) async {
      await pumpSignedIn(tester);

      expect(find.text('Sell on AgroBenta'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Become a Seller'), findsOneWidget);
    });

    testWidgets('opens the verification status screen', (
      WidgetTester tester,
    ) async {
      await pumpSignedIn(tester);
      await tester.ensureVisible(find.text('Become a Seller'));
      await tester.tap(find.text('Become a Seller'));
      await settleAuth(tester, frames: 16);

      expect(find.byType(SellerVerificationScreen), findsOneWidget);
    });

    testWidgets('points an open application at its status, not a new form', (
      WidgetTester tester,
    ) async {
      await pumpSignedIn(
        tester,
        verification: sellerVerificationJson(status: 'pending_review'),
      );

      expect(find.text('Verification under review'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Become a Seller'),
        findsNothing,
        reason: 'a second application would be refused with a 409',
      );
      expect(
        find.widgetWithText(OutlinedButton, 'View status'),
        findsOneWidget,
      );
    });

    testWidgets('offers a resubmission after a rejection', (
      WidgetTester tester,
    ) async {
      await pumpSignedIn(
        tester,
        verification: sellerVerificationJson(
          status: 'rejected',
          adminNote: 'Name does not match the reference.',
        ),
      );

      expect(find.text('Verification not approved'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Resubmit Verification'),
        findsOneWidget,
      );
    });

    testWidgets('never offers a seller the form again', (
      WidgetTester tester,
    ) async {
      // `/auth/me` says seller. A seller is not shown a way to apply, because
      // the account already has capability and the endpoint would answer 403.
      await pumpSignedIn(
        tester,
        user: userJson(sellerCapability: 'seller'),
        verification: sellerVerificationJson(status: 'approved'),
      );

      expect(find.text('Your account is a seller.'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Become a Seller'),
        findsNothing,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'View verification'),
        findsOneWidget,
      );
    });

    testWidgets('reflects capability from the account, not the application', (
      WidgetTester tester,
    ) async {
      // A rejected application on an account that is already a seller is a
      // contradictory state, and the card must not talk the user into applying
      // again on the strength of the rejection.
      await pumpSignedIn(
        tester,
        user: userJson(sellerCapability: 'seller'),
        verification: sellerVerificationJson(status: 'rejected'),
      );

      expect(find.widgetWithText(FilledButton, 'Resubmit Verification'), findsNothing);
      expect(find.text('Seller'), findsOneWidget);
    });
  });

  testWidgets('offers a way into the marketplace', (WidgetTester tester) async {
    await pumpSignedIn(tester);

    expect(find.text('Browse the marketplace'), findsOneWidget);
    expect(
      find.text('Go to marketplace'),
      findsNothing,
      reason: 'without a callback the card renders without a dead button',
    );
  });

  testWidgets('shows the marketplace button when a destination is supplied', (
    WidgetTester tester,
  ) async {
    final AuthController controller = AuthController(
      buildAuthRepository(
        tokenStore,
        (_) async => http.Response(
          jsonEncode(successEnvelope(data: userJson())),
          200,
        ),
      ),
    );
    addTearDown(controller.dispose);

    tokenStore.token = 'stored-token';
    await controller.restoreSession();

    await tester.pumpWidget(
      AuthScope(
        controller: controller,
        child: NeverSubmittedVerificationScope(
          child: MaterialApp(
            home: BuyerHomeScreen(onBrowseMarketplace: () {}),
          ),
        ),
      ),
    );
    await settleAuth(tester, frames: 12);

    final OutlinedButton button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Go to marketplace'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('has a labelled sign-out action', (WidgetTester tester) async {
    await pumpSignedIn(tester);

    final TextButton button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Sign out'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('a sign-out failure keeps the user on the screen', (
    WidgetTester tester,
  ) async {
    final AuthController controller = AuthController(
      buildAuthRepository(tokenStore, (RecordedRequest entry) async {
        if (entry.apiPath == '/auth/logout') {
          throw http.ClientException('connection refused');
        }
        return http.Response(jsonEncode(successEnvelope(data: userJson())), 200);
      }),
    );
    addTearDown(controller.dispose);

    tokenStore.token = 'stored-token';
    await controller.restoreSession();
    await tester.pumpWidget(
      AuthScope(
        controller: controller,
        child: const NeverSubmittedVerificationScope(
          child: MaterialApp(home: BuyerHomeScreen()),
        ),
      ),
    );
    await settleAuth(tester, frames: 12);

    await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
    await settleAuth(tester, frames: 12);

    expect(find.byType(BuyerHomeScreen), findsOneWidget);
    expect(find.text('Welcome, Ana Reyes'), findsOneWidget);
    expect(
      tokenStore.token,
      'stored-token',
      reason: 'a failed sign-out must not silently drop the session',
    );
  });

  testWidgets('degrades without a user instead of crashing', (
    WidgetTester tester,
  ) async {
    final AuthController controller = AuthController(
      buildAuthRepository(tokenStore, (_) async => fail('no request expected')),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: AuthScope(controller: controller, child: const BuyerHomeScreen()),
      ),
    );
    await settleAuth(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('No account loaded.'), findsOneWidget);
    expect(find.byType(User), findsNothing);
  });
}
