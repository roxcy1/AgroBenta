import 'dart:convert';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_controller.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_scope.dart';
import 'package:agrobenta_mobile/features/home/view/buyer_home_screen.dart';
import 'package:agrobenta_mobile/features/marketplace/state/marketplace_controller.dart';
import 'package:agrobenta_mobile/features/marketplace/state/marketplace_scope.dart';
import 'package:agrobenta_mobile/features/marketplace/views/listing_detail_screen.dart';
import 'package:agrobenta_mobile/features/notifications/state/notifications_controller.dart';
import 'package:agrobenta_mobile/features/notifications/state/notifications_scope.dart';
import 'package:agrobenta_mobile/models/user.dart';
import 'package:agrobenta_mobile/repositories/marketplace_repository.dart';
import 'package:agrobenta_mobile/repositories/notification_repository.dart';
import 'package:agrobenta_mobile/services/notification_service.dart';
import 'package:agrobenta_mobile/widgets/temporary_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/auth_app_harness.dart';
import '../../support/auth_fakes.dart';
import '../../support/marketplace_fakes.dart';
import '../../support/seller_verification_app_harness.dart';

void main() {
  late FakeTokenStore tokenStore;

  setUp(() => tokenStore = FakeTokenStore());

  /// Finds a rendered Font Awesome glyph. [Finder.byIcon] cannot be used:
  /// `font_awesome_flutter` 11.x types the stored glyph as [FaIconData], while
  /// the inherited [Icon.icon] getter exposes only its `.data` (an `IconData`).
  Finder faIcon(FaIconData icon) => find.byWidgetPredicate(
    (Widget widget) => widget is FaIcon && widget.icon == icon.data,
    description: 'FaIcon $icon',
  );

  /// Pumps the home screen with an already-restored session, which is the only
  /// way the gate would ever show it.
  ///
  /// [onMarketplace] replaces the marketplace transport (listings plus the
  /// detail route this screen pushes); it defaults to one canonical fixture
  /// page. [recorded] collects every marketplace request, so a test can assert
  /// on what was actually sent.
  Future<void> pumpSignedIn(
    WidgetTester tester, {
    Map<String, dynamic>? user,
    Future<http.Response> Function(RecordedRequest request)? onMarketplace,
    List<RecordedRequest>? recorded,
    VoidCallback? onBrowseMarketplace,
    VoidCallback? onOpenProfile,
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

    final MarketplaceRepository marketplaceRepository = buildMarketplaceRepository(
      tokenStore,
      (RecordedRequest request) async {
        if (onMarketplace != null) {
          return onMarketplace(request);
        }
        // The listing-detail route this screen pushes must get a valid answer
        // too, exactly as the marketplace's own navigation tests arrange.
        if (request.apiPath.startsWith('/listings/')) {
          return listingDetailResponse();
        }
        return marketplaceListResponse();
      },
      recorded: recorded,
    );
    final MarketplaceController marketplaceController = MarketplaceController(
      marketplaceRepository,
    );
    addTearDown(marketplaceController.dispose);

    final NotificationRepository notificationRepository = NotificationRepository(
      NotificationService(
        ApiClient(
          tokenStorage: tokenStore,
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode(successEnvelope(data: <String, dynamic>{'count': 0})),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            ),
          ),
        ),
      ),
    );
    final NotificationsController notificationsController =
        NotificationsController(notificationRepository);
    addTearDown(notificationsController.dispose);

    tokenStore.token = 'stored-token';
    await controller.restoreSession();

    await tester.pumpWidget(
      // Scopes **above** `MaterialApp`, as `main.dart` does. A route pushed
      // onto the navigator is a sibling of `home` inside the overlay, so a
      // scope nested in `home` would be invisible to the pushed detail or
      // verification screens — which is the arrangement these tests are in a
      // position to catch.
      AuthScope(
        controller: controller,
        child: NeverSubmittedVerificationScope(
          child: MarketplaceScope(
            repository: marketplaceRepository,
            controller: marketplaceController,
            child: NotificationsScope(
              repository: notificationRepository,
              controller: notificationsController,
              child: MaterialApp(
                home: BuyerHomeScreen(
                  onBrowseMarketplace: onBrowseMarketplace,
                  onOpenProfile: onOpenProfile,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settleAuth(tester, frames: 12);
  }

  testWidgets('greets the user', (
    WidgetTester tester,
  ) async {
    await pumpSignedIn(tester);

    expect(find.text('Hello, Ana Reyes!'), findsOneWidget);
    expect(find.text('Happy trading!'), findsOneWidget);
  });

  testWidgets('leads with the brand, using the centralized logo placeholder', (
    WidgetTester tester,
  ) async {
    await pumpSignedIn(tester);

    expect(find.byType(TemporaryLogo), findsOneWidget);
    expect(find.text('AgroBenta'), findsOneWidget);
    expect(find.text('Buy. Sell. Grow. Together.'), findsOneWidget);
  });

  group('recent listings', () {
    testWidgets('are rendered from the marketplace API, not invented', (
      WidgetTester tester,
    ) async {
      await pumpSignedIn(tester);

      expect(find.text('Recent Listings'), findsOneWidget);
      // Every field comes from the `GET /listings` fixture: species, breed,
      // the compact peso price and the location, on the shared ListingCard.
      expect(find.text('Holstein'), findsOneWidget);
      expect(find.text('₱42,500'), findsOneWidget);
      expect(find.text('Mabalacat, Pampanga'), findsOneWidget);
      expect(find.text('Cattle'), findsWidgets);

      // The design forbids a "featured" claim the backend cannot back, and the
      // screen must carry no placeholder copy of its own.
      expect(find.text('Featured Livestock'), findsNothing);
      expect(find.textContaining('later releases'), findsNothing);
    });

    testWidgets('show an empty state when the marketplace has none', (
      WidgetTester tester,
    ) async {
      await pumpSignedIn(
        tester,
        onMarketplace: (RecordedRequest request) async =>
            marketplaceListResponse(listings: <Map<String, dynamic>>[]),
      );

      expect(find.text('No active listings yet.'), findsOneWidget);
    });

    testWidgets('offer a retry when the marketplace request fails', (
      WidgetTester tester,
    ) async {
      await pumpSignedIn(
        tester,
        onMarketplace: (RecordedRequest request) async =>
            http.Response(jsonEncode('Server exploded.'), 500),
      );

      // The rest of the screen stays usable; only the section reports.
      expect(find.text('Hello, Ana Reyes!'), findsOneWidget);
      expect(
        find.widgetWithText(TextButton, 'Try again'),
        findsOneWidget,
      );
    });

    testWidgets('a tapped listing opens its detail screen', (
      WidgetTester tester,
    ) async {
      await pumpSignedIn(tester);

      await tester.ensureVisible(find.text('Holstein'));
      await tester.tap(find.text('Holstein'));
      await settleAuth(tester, frames: 16);

      expect(find.byType(ListingDetailScreen), findsOneWidget);
    });
  });

  group('categories', () {
    testWidgets('apply the existing livestock_type filter and follow it', (
      WidgetTester tester,
    ) async {
      bool followedToMarketplace = false;
      final List<RecordedRequest> recorded = <RecordedRequest>[];
      await pumpSignedIn(
        tester,
        recorded: recorded,
        onBrowseMarketplace: () => followedToMarketplace = true,
      );

      await tester.ensureVisible(faIcon(FontAwesomeIcons.cow));
      await tester.tap(faIcon(FontAwesomeIcons.cow));
      await settleAuth(tester, frames: 12);

      expect(followedToMarketplace, isTrue);
      expect(
        recorded
            .where(
              (RecordedRequest request) =>
                  request.apiPath == '/listings' &&
                  request.query['livestock_type'] == 'Cattle',
            ),
          isNotEmpty,
        reason:
            'a category tap must reuse the marketplace exact-match filter, '
            'not invent a query',
      );
    });

    testWidgets('the grid carries exactly the five designed categories', (
      WidgetTester tester,
    ) async {
      await pumpSignedIn(tester);

      for (final String label in <String>[
        'Cattle',
        'Goats',
        'Pigs',
        'Poultry',
        'Sheep',
      ]) {
        expect(find.text(label), findsWidgets, reason: 'missing $label');
      }
      expect(faIcon(FontAwesomeIcons.cow), findsOneWidget);
      expect(faIcon(FontAwesomeIcons.paw), findsOneWidget);
      expect(faIcon(FontAwesomeIcons.bacon), findsOneWidget);
      expect(faIcon(FontAwesomeIcons.kiwiBird), findsOneWidget);
      expect(faIcon(FontAwesomeIcons.feather), findsOneWidget);
    });
  });

  group('search', () {
    testWidgets('commit to the shared marketplace state on submit', (
      WidgetTester tester,
    ) async {
      bool followedToMarketplace = false;
      final List<RecordedRequest> recorded = <RecordedRequest>[];
      await pumpSignedIn(
        tester,
        recorded: recorded,
        onBrowseMarketplace: () => followedToMarketplace = true,
      );

      await tester.enterText(find.byType(TextField), 'holstein');
      // The keyboard action, not a raw `submit()`: this is what fires the
      // field's `onSubmitted` exactly as a search key would.
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settleAuth(tester, frames: 12);

      expect(followedToMarketplace, isTrue);
      expect(
        recorded
            .where(
              (RecordedRequest request) =>
                  request.apiPath == '/listings' &&
                  request.query['search'] == 'holstein',
            ),
          isNotEmpty,
        reason: 'the typed query must reach GET /listings as ?search=',
      );
    });

    testWidgets('offer a clear control only while there is text', (
      WidgetTester tester,
    ) async {
      await pumpSignedIn(tester);

      expect(find.byTooltip('Clear search'), findsNothing);

      await tester.enterText(find.byType(TextField), 'pampanga');
      await settleAuth(tester);

      expect(find.byTooltip('Clear search'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear search'));
      await settleAuth(tester);

      final TextField field = tester.widget<TextField>(
        find.byType(TextField),
      );
      expect(field.controller!.text, isEmpty);
      expect(find.byTooltip('Clear search'), findsNothing);
    });
  });

  group('hero banner', () {
    testWidgets('offers the marketplace CTA when a destination is supplied', (
      WidgetTester tester,
    ) async {
      await pumpSignedIn(tester, onBrowseMarketplace: () {});

      expect(
        find.text('Quality Livestock for a Better Tomorrow'),
        findsOneWidget,
      );
      final FilledButton button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Explore Now'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('renders no dead CTA without a destination', (
      WidgetTester tester,
    ) async {
      await pumpSignedIn(tester);

      expect(
        find.text('Quality Livestock for a Better Tomorrow'),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Explore Now'), findsNothing);
    });
  });

  group('header profile action', () {
    testWidgets('is present and wired when a destination is supplied', (
      WidgetTester tester,
    ) async {
      bool openedProfile = false;
      await pumpSignedIn(tester, onOpenProfile: () => openedProfile = true);

      expect(find.byTooltip('Profile'), findsOneWidget);

      await tester.tap(find.byTooltip('Profile'));
      expect(openedProfile, isTrue);
    });

    testWidgets('is omitted without a destination', (
      WidgetTester tester,
    ) async {
      await pumpSignedIn(tester);

      expect(find.byTooltip('Profile'), findsNothing);
    });
  });

  group('seller listings entry', () {
    testWidgets('is hidden for a buyer', (WidgetTester tester) async {
      await pumpSignedIn(tester);

      expect(find.text('My Listings'), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Manage my listings'),
        findsNothing,
        reason: 'a buyer would be answered 403 by every request behind it',
      );
    });

    testWidgets('appears for a seller', (WidgetTester tester) async {
      await pumpSignedIn(tester, user: userJson(sellerCapability: 'seller'));

      expect(find.text('My Listings'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Manage my listings'),
        findsOneWidget,
      );
    });
  });

  testWidgets('degrades without a user instead of crashing', (
    WidgetTester tester,
  ) async {
    final AuthController controller = AuthController(
      buildAuthRepository(tokenStore, (_) async => fail('no request expected')),
    );
    addTearDown(controller.dispose);

    final MarketplaceRepository marketplaceRepository = buildMarketplaceRepository(
      tokenStore,
      (_) async => marketplaceListResponse(),
    );
    final MarketplaceController marketplaceController = MarketplaceController(
      marketplaceRepository,
    );
    addTearDown(marketplaceController.dispose);

    final NotificationRepository notificationRepository = NotificationRepository(
      NotificationService(
        ApiClient(
          tokenStorage: tokenStore,
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode(successEnvelope(data: <String, dynamic>{'count': 0})),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            ),
          ),
        ),
      ),
    );
    final NotificationsController notificationsController =
        NotificationsController(notificationRepository);
    addTearDown(notificationsController.dispose);

    // No restore, so the signed-in state carries no user — the contract
    // surprise the screen must survive rather than red-screen on. The scopes
    // are still present, because `main.dart` installs them regardless of
    // session state and the screen's `initState` reads them before `build`
    // decides there is nothing to show.
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScope(
          controller: controller,
          child: NeverSubmittedVerificationScope(
            child: MarketplaceScope(
              repository: marketplaceRepository,
              controller: marketplaceController,
              child: NotificationsScope(
                repository: notificationRepository,
                controller: notificationsController,
                child: const BuyerHomeScreen(),
              ),
            ),
          ),
        ),
      ),
    );
    await settleAuth(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('No account loaded.'), findsOneWidget);
    expect(find.byType(User), findsNothing);
  });
}
