import 'dart:convert';

import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_controller.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_scope.dart';
import 'package:agrobenta_mobile/features/inquiries/state/inquiry_scope.dart';
import 'package:agrobenta_mobile/features/inquiries/view/inquire_screen.dart';
import 'package:agrobenta_mobile/features/livestock_types/state/livestock_types_controller.dart';
import 'package:agrobenta_mobile/features/livestock_types/state/livestock_types_scope.dart';
import 'package:agrobenta_mobile/features/marketplace/state/marketplace_controller.dart';
import 'package:agrobenta_mobile/features/marketplace/state/marketplace_scope.dart';
import 'package:agrobenta_mobile/features/marketplace/views/listing_detail_screen.dart';
import 'package:agrobenta_mobile/features/messaging/state/conversations_controller.dart';
import 'package:agrobenta_mobile/features/messaging/state/messaging_scope.dart';
import 'package:agrobenta_mobile/features/messaging/view/chat_screen.dart';
import 'package:agrobenta_mobile/features/offers/state/offer_scope.dart';
import 'package:agrobenta_mobile/features/seller_profile/view/seller_profile_screen.dart';
import 'package:agrobenta_mobile/repositories/inquiry_repository.dart';
import 'package:agrobenta_mobile/repositories/marketplace_repository.dart';
import 'package:agrobenta_mobile/repositories/messaging_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/inquiry_fakes.dart';
import '../../support/livestock_type_fakes.dart';
import '../../support/marketplace_fakes.dart';
import '../../support/messaging_fakes.dart';
import '../../support/offer_fakes.dart';
import '../../support/seller_profile_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  setUp(() {
    tokenStore = FakeTokenStore('token');
    recorded = <RecordedRequest>[];
  });

  Future<void> settle(WidgetTester tester, {int frames = 12}) async {
    for (int frame = 0; frame < frames; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Pumps the listing detail as the app does: every scope it can reach sits
  /// above `MaterialApp`, one transport answers every endpoint the screen and
  /// the inquiry form it can push will hit.
  Future<void> pumpDetail(
    WidgetTester tester, {
    required int sellerId,
    required int viewerId,
    bool sellerIsVerified = true,
    List<Object?>? photos,
    int completedSales = 0,
    String? ageInformation = 'known',
    String? weightInformation = 'measured',
  }) async {
    Future<http.Response> transport(RecordedRequest request) async {
      final String path = request.apiPath;

      if (path == '/listings/12') {
        return listingDetailResponse(
          listing: listingJson(
            seller: sellerJson(id: sellerId, isVerified: sellerIsVerified),
            photos: photos,
            completedSales: completedSales,
            ageInformation: ageInformation,
            weightInformation: weightInformation,
          ),
        );
      }
      if (path == '/marketplace/sellers/$sellerId') {
        return sellerProfileResponse(
          profile: sellerProfileJson(
            id: sellerId,
            name: 'Rizal Farms',
            activeListingsCount: 0,
          ),
        );
      }
      if (path == '/marketplace/sellers/$sellerId/listings') {
        return sellerListingsResponse(
          listings: <Map<String, dynamic>>[],
          total: 0,
        );
      }
      return marketplaceListResponse();
    }

    final MarketplaceRepository marketplaceRepository =
        buildMarketplaceRepository(tokenStore, transport, recorded: recorded);
    final MarketplaceController marketplaceController = MarketplaceController(
      marketplaceRepository,
    );
    addTearDown(marketplaceController.dispose);

    final AuthController authController = AuthController(
      buildAuthRepository(
        tokenStore,
        (_) async => http.Response(
          jsonEncode(successEnvelope(data: userJson(id: viewerId))),
          200,
        ),
      ),
    );
    addTearDown(authController.dispose);
    tokenStore.token = 'stored-token';
    await authController.restoreSession();

    // The screen's Inquire action pushes a form over this route, so the
    // repository it reads must be in scope exactly as `main.dart` installs it.
    final InquiryRepository inquiryRepository = buildInquiryRepository(
      tokenStore,
      (RecordedRequest request) async => request.method == 'POST'
          ? inquiryCreatedResponse()
          : marketplaceListResponse(),
      recorded: recorded,
    );

    final MessagingRepository messagingRepository = buildMessagingRepository(
      tokenStore,
      (RecordedRequest request) async {
        if (request.apiPath.contains('/read')) {
          return threadReadResponse();
        }
        if (request.apiPath.contains('/messages')) {
          return messageThreadResponse();
        }
        return conversationsResponse();
      },
      recorded: recorded,
    );
    final ConversationsController conversationsController =
        ConversationsController(messagingRepository);
    addTearDown(conversationsController.dispose);

    final offerRepository = buildOfferRepository(
      tokenStore,
      (_) async => offersResponse(offers: <Map<String, dynamic>>[]),
    );

    // The pushed seller profile builds its category chips from the shared
    // catalog, so the harness installs the scope `main.dart` provides.
    final catalogRepository = buildLivestockTypeRepository(tokenStore);
    final LivestockTypesController catalogController = LivestockTypesController(
      catalogRepository,
    );
    addTearDown(catalogController.dispose);
    await catalogController.ensureLoaded();

    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AuthScope(
        controller: authController,
        child: MarketplaceScope(
          repository: marketplaceRepository,
          controller: marketplaceController,
          child: InquiryScope(
            repository: inquiryRepository,
            child: MessagingScope(
              repository: messagingRepository,
              conversationsController: conversationsController,
              child: OfferScope(
                repository: offerRepository,
                child: LivestockTypesScope(
                  repository: catalogRepository,
                  controller: catalogController,
                  child: MaterialApp(
                    theme: AppTheme.light(),
                    home: const ListingDetailScreen(listingId: 12),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  group('listing detail content', () {
    testWidgets('renders only the fields the API returned', (
      WidgetTester tester,
    ) async {
      await pumpDetail(tester, sellerId: 3, viewerId: 7);

      // Summary: species, title, price, availability, location.
      expect(find.text('Cattle'), findsOneWidget);
      expect(find.text('Holstein'), findsOneWidget);
      expect(find.text('₱42,500.00'), findsOneWidget);
      expect(find.text('4 heads'), findsOneWidget);
      expect(find.text('Mabalacat, Pampanga'), findsOneWidget);

      // Attributes.
      expect(find.text('Known Age'), findsOneWidget);
      expect(find.text('18 months'), findsOneWidget);
      expect(find.text('Measured Weight'), findsOneWidget);
      expect(find.text('320.5 kg'), findsOneWidget);
      expect(find.text('Gender'), findsOneWidget);
      expect(find.text('Female'), findsOneWidget);

      // Description and seller.
      expect(
        find.text('Healthy Holstein heifers, ready for breeding.'),
        findsOneWidget,
      );
      expect(find.text('Rizal Farms'), findsOneWidget);
    });

    testWidgets('labels seller-estimated measurements and explains them', (
      WidgetTester tester,
    ) async {
      await pumpDetail(
        tester,
        sellerId: 3,
        viewerId: 7,
        ageInformation: 'estimated',
        weightInformation: 'estimated',
      );

      expect(find.text('Estimated Age'), findsOneWidget);
      expect(find.text('Estimated Weight'), findsOneWidget);
      expect(
        find.text(
          'Estimated age or weight is provided by the seller and is not '
          'independently verified.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows no placeholder rating', (WidgetTester tester) async {
      await pumpDetail(tester, sellerId: 3, viewerId: 7, completedSales: 3);

      expect(find.text('4.8 · 24 reviews'), findsNothing);
      expect(find.byIcon(Icons.star_rounded), findsNothing);
    });

    testWidgets('shows a neutral placeholder when there is no photo', (
      WidgetTester tester,
    ) async {
      await pumpDetail(tester, sellerId: 3, viewerId: 7);

      // Default fixture has no photos; nothing is synthesised to fill the gap.
      expect(find.text('No photo'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('does not invent a favorite or seller avatar', (
      WidgetTester tester,
    ) async {
      await pumpDetail(
        tester,
        sellerId: 3,
        viewerId: 7,
        sellerIsVerified: false,
      );

      // No favorites feature and no seller avatar are fabricated.
      expect(find.byIcon(Icons.favorite_border), findsNothing);
      expect(find.byIcon(Icons.favorite), findsNothing);
      expect(find.textContaining('Verified'), findsNothing);
    });

    testWidgets('shows the approved seller badge beside the seller name', (
      WidgetTester tester,
    ) async {
      await pumpDetail(tester, sellerId: 3, viewerId: 7);

      await tester.ensureVisible(find.byKey(listingSellerCardKey));
      expect(find.text('Rizal Farms'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
    });

    testWidgets('shows page indicators only when there are several photos', (
      WidgetTester tester,
    ) async {
      await pumpDetail(
        tester,
        sellerId: 3,
        viewerId: 7,
        photos: <Object?>[
          'https://cdn.example.test/front.jpg',
          'https://cdn.example.test/side.jpg',
        ],
      );

      expect(_indicatorLabels(tester), <String>['Image 1 of 2']);
    });

    testWidgets('a single photo gets no page indicator', (
      WidgetTester tester,
    ) async {
      await pumpDetail(
        tester,
        sellerId: 3,
        viewerId: 7,
        photos: <Object?>['https://cdn.example.test/front.jpg'],
      );

      expect(_indicatorLabels(tester), isEmpty);
    });
  });

  group('listing detail actions', () {
    testWidgets('a non-owner gets Ask Seller and I am Interested', (
      WidgetTester tester,
    ) async {
      await pumpDetail(tester, sellerId: 3, viewerId: 7);

      expect(find.widgetWithText(OutlinedButton, 'Ask Seller'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, "I'm Interested"),
        findsOneWidget,
      );
      expect(find.text('Inquire'), findsNothing);
    });

    testWidgets('the owner gets no actions', (WidgetTester tester) async {
      await pumpDetail(tester, sellerId: 7, viewerId: 7);

      expect(find.text('Ask Seller'), findsNothing);
      expect(find.text("I'm Interested"), findsNothing);
    });

    testWidgets('Ask Seller opens the conversation and creates nothing', (
      WidgetTester tester,
    ) async {
      await pumpDetail(tester, sellerId: 3, viewerId: 7);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Ask Seller'));
      await settle(tester);

      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
      expect(find.byType(InquireScreen), findsNothing);
      expect(
        recorded.where(
          (RecordedRequest r) =>
              r.method == 'POST' &&
              (r.apiPath == '/messages' || r.apiPath == '/inquiries'),
        ),
        isEmpty,
        reason: 'opening chat is navigation, not a message or an inquiry',
      );
    });

    testWidgets("I'm Interested opens the inquiry form and sends nothing", (
      WidgetTester tester,
    ) async {
      await pumpDetail(tester, sellerId: 3, viewerId: 7);

      await tester.tap(find.widgetWithText(FilledButton, "I'm Interested"));
      await settle(tester);

      expect(find.byType(InquireScreen), findsOneWidget);
      expect(find.text('Message (optional)'), findsOneWidget);
      expect(
        recorded.where((RecordedRequest r) => r.method == 'POST'),
        isEmpty,
        reason: 'opening the form is navigation, not a submission',
      );
    });

    testWidgets('the seller card opens that seller public profile', (
      WidgetTester tester,
    ) async {
      await pumpDetail(tester, sellerId: 3, viewerId: 7);

      await tester.ensureVisible(find.byKey(listingSellerCardKey));
      await settle(tester);
      await tester.tap(find.byKey(listingSellerCardKey));
      await settle(tester);

      expect(find.byType(SellerProfileScreen), findsOneWidget);
      expect(find.text('Seller Profile'), findsOneWidget);
      expect(
        recorded.where((RecordedRequest r) => r.method == 'POST'),
        isEmpty,
        reason: 'opening a profile is navigation, not a message or inquiry',
      );
    });

    testWidgets('returning from the profile preserves the listing detail', (
      WidgetTester tester,
    ) async {
      await pumpDetail(tester, sellerId: 3, viewerId: 7);

      await tester.ensureVisible(find.byKey(listingSellerCardKey));
      await settle(tester);
      await tester.tap(find.byKey(listingSellerCardKey));
      await settle(tester);
      expect(find.byType(SellerProfileScreen), findsOneWidget);

      await tester.pageBack();
      await settle(tester);

      expect(find.byType(SellerProfileScreen), findsNothing);
      expect(find.text('Holstein'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Ask Seller'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, "I'm Interested"),
        findsOneWidget,
      );
    });
  });
}

/// The accessibility labels of any gallery page indicators in the tree.
///
/// Read off the `Semantics` widgets directly rather than through
/// `find.bySemanticsLabel`, so the test does not have to stand up the semantics
/// tree (and remember to tear it down).
List<String> _indicatorLabels(WidgetTester tester) {
  return tester
      .widgetList<Semantics>(find.byType(Semantics))
      .map((Semantics semantics) => semantics.properties.label)
      .whereType<String>()
      .where((String label) => label.startsWith('Image '))
      .toList(growable: false);
}
