import 'dart:convert';

import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_controller.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_scope.dart';
import 'package:agrobenta_mobile/features/livestock_types/state/livestock_types_controller.dart';
import 'package:agrobenta_mobile/features/livestock_types/state/livestock_types_scope.dart';
import 'package:agrobenta_mobile/features/marketplace/state/marketplace_controller.dart';
import 'package:agrobenta_mobile/features/marketplace/state/marketplace_scope.dart';
import 'package:agrobenta_mobile/features/marketplace/views/listing_detail_screen.dart';
import 'package:agrobenta_mobile/features/marketplace/widgets/listing_card.dart';
import 'package:agrobenta_mobile/features/seller_profile/state/seller_listing_filters.dart';
import 'package:agrobenta_mobile/features/seller_profile/view/seller_profile_screen.dart';
import 'package:agrobenta_mobile/features/seller_profile/widgets/seller_profile_tab_bar.dart';
import 'package:agrobenta_mobile/features/user_reports/state/user_report_scope.dart';
import 'package:agrobenta_mobile/features/user_reports/view/report_user_screen.dart';
import 'package:agrobenta_mobile/repositories/marketplace_repository.dart';
import 'package:agrobenta_mobile/repositories/user_report_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/livestock_type_fakes.dart';
import '../../support/marketplace_fakes.dart';
import '../../support/seller_profile_fakes.dart';
import '../../support/user_report_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  setUp(() {
    tokenStore = FakeTokenStore('valid-mobile-token');
    recorded = <RecordedRequest>[];
  });

  Future<void> settle(WidgetTester tester, {int frames = 16}) async {
    for (int frame = 0; frame < frames; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Pumps the profile with the scopes `main.dart` installs above
  /// `MaterialApp`: the marketplace repository (which the screen reads) and the
  /// auth controller (which the pushed listing detail reads).
  Future<void> pumpProfile(
    WidgetTester tester, {
    required Future<http.Response> Function(RecordedRequest request) handler,
    int sellerId = 3,
    int viewerId = 7,
  }) async {
    final MarketplaceRepository repository = buildMarketplaceRepository(
      tokenStore,
      handler,
      recorded: recorded,
    );
    final MarketplaceController marketplaceController = MarketplaceController(
      repository,
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

    // The Listings filter chips are built from the backend-owned catalog, so
    // the harness installs the same scope `main.dart` does.
    final catalogRepository = buildLivestockTypeRepository(tokenStore);
    final LivestockTypesController catalogController = LivestockTypesController(
      catalogRepository,
    );
    addTearDown(catalogController.dispose);
    await catalogController.ensureLoaded();

    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UserReportScope(
        repository: UserReportRepository(
          buildUserReportService(
            tokenStore,
            (_) async => userReportCreatedResponse(),
          ),
        ),
        child: AuthScope(
          controller: authController,
          child: MarketplaceScope(
            repository: repository,
            controller: marketplaceController,
            child: LivestockTypesScope(
              repository: catalogRepository,
              controller: catalogController,
              child: MaterialApp(
                theme: AppTheme.light(),
                home: SellerProfileScreen(sellerId: sellerId),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<http.Response> profileHandler(
    RecordedRequest request, {
    bool verified = true,
    String? bio,
    String? avatarUrl,
    List<Map<String, dynamic>>? listings,
    int lastPage = 1,
    int total = 1,
  }) async {
    if (request.apiPath == '/marketplace/sellers/3') {
      return sellerProfileResponse(
        profile: sellerProfileJson(
          isVerified: verified,
          bio: bio,
          avatarUrl: avatarUrl,
          activeListingsCount: total,
        ),
      );
    }
    if (request.apiPath == '/marketplace/sellers/3/listings') {
      return sellerListingsResponse(
        listings: listings,
        lastPage: lastPage,
        total: total,
      );
    }
    if (request.apiPath == '/listings/12') {
      return listingDetailResponse();
    }
    return sellerNotFoundResponse();
  }

  testWidgets('renders the public header, summary and profile tab', (
    WidgetTester tester,
  ) async {
    await pumpProfile(
      tester,
      handler: (RecordedRequest request) => profileHandler(
        request,
        bio: 'Third-generation cattle farmer in Trinidad.',
        total: 2,
      ),
    );

    expect(find.text('Seller Profile'), findsOneWidget);
    expect(find.text('Joseph Basilad'), findsOneWidget);
    expect(find.text('Barangay San Isidro, Trinidad, Bohol'), findsNWidgets(2));
    expect(find.text('Verified Seller'), findsNWidgets(2));
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Active listings'), findsOneWidget);
    expect(find.text('September 2026'), findsNWidgets(2));

    // Profile tab rows.
    expect(find.text('Seller information'), findsOneWidget);
    expect(find.text('Verification status'), findsOneWidget);
    expect(find.text('Public location'), findsOneWidget);
    expect(find.text('Member since'), findsWidgets);
    expect(find.text('About'), findsOneWidget);
    expect(
      find.text('Third-generation cattle farmer in Trinidad.'),
      findsOneWidget,
    );

    // Private data is not part of the model or the screen.
    expect(find.textContaining('@'), findsNothing);
    expect(find.textContaining('0917'), findsNothing);
    expect(find.textContaining('Purok'), findsNothing);
  });

  testWidgets('an unverified seller has no badge but states the status', (
    WidgetTester tester,
  ) async {
    await pumpProfile(
      tester,
      handler: (RecordedRequest request) =>
          profileHandler(request, verified: false),
    );

    expect(find.byIcon(Icons.verified), findsNothing);
    expect(find.text('Verified Seller'), findsNothing);
    expect(find.text('Not verified'), findsOneWidget);
  });

  testWidgets('a profile without a location or biography omits them', (
    WidgetTester tester,
  ) async {
    await pumpProfile(
      tester,
      handler: (RecordedRequest request) async {
        if (request.apiPath == '/marketplace/sellers/3') {
          return sellerProfileResponse(
            profile: sellerProfileJson(publicLocation: null, bio: null),
          );
        }
        return sellerListingsResponse(listings: <Map<String, dynamic>>[]);
      },
    );

    expect(find.text('About'), findsNothing);
    expect(find.text('Verified Seller'), findsWidgets);
    expect(find.text('Not provided'), findsOneWidget);
  });

  testWidgets('the Listings tab loads lazily and reuses the marketplace card', (
    WidgetTester tester,
  ) async {
    await pumpProfile(
      tester,
      handler: (RecordedRequest request) => profileHandler(request, total: 1),
    );

    // The profile request happened; the listings request has not.
    expect(
      recorded.where((RecordedRequest r) => r.apiPath.endsWith('/listings')),
      isEmpty,
    );

    await tester.tap(find.text('Listings'));
    await settle(tester);

    expect(
      recorded.where((RecordedRequest r) => r.apiPath.endsWith('/listings')),
      hasLength(1),
    );
    expect(find.byType(ListingCard), findsOneWidget);
    expect(find.text('No active listings'), findsNothing);
  });

  testWidgets('an empty Listings tab explains the absence', (
    WidgetTester tester,
  ) async {
    await pumpProfile(
      tester,
      handler: (RecordedRequest request) async {
        if (request.apiPath == '/marketplace/sellers/3') {
          return sellerProfileResponse(
            profile: sellerProfileJson(activeListingsCount: 0),
          );
        }
        return sellerListingsResponse(
          listings: <Map<String, dynamic>>[],
          total: 0,
        );
      },
    );

    await tester.tap(find.text('Listings'));
    await settle(tester);

    expect(find.text('No active listings'), findsOneWidget);
    expect(
      find.text('This seller has no listings available right now.'),
      findsOneWidget,
    );
  });

  testWidgets('a listing card opens the existing listing detail', (
    WidgetTester tester,
  ) async {
    await pumpProfile(
      tester,
      handler: (RecordedRequest request) => profileHandler(request),
    );

    await tester.tap(find.text('Listings'));
    await settle(tester);
    await tester.tap(find.byType(ListingCard));
    await settle(tester);

    expect(find.byType(ListingDetailScreen), findsOneWidget);
    expect(recorded.last.apiPath, '/listings/12');
  });

  testWidgets('an unavailable seller shows a non-retryable state', (
    WidgetTester tester,
  ) async {
    await pumpProfile(tester, handler: (_) async => sellerNotFoundResponse());

    expect(find.text('Seller profile unavailable'), findsOneWidget);
    expect(
      find.text(
        'This seller may no longer have an active account or public listings.',
      ),
      findsOneWidget,
    );
    expect(find.text('Back to listing'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('a failed profile load can be retried', (
    WidgetTester tester,
  ) async {
    var fail = true;
    await pumpProfile(
      tester,
      handler: (RecordedRequest request) async {
        if (request.apiPath == '/marketplace/sellers/3' && fail) {
          return http.Response(
            jsonEncode(<String, Object>{
              'success': false,
              'message': 'Server exploded.',
            }),
            500,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        return profileHandler(request);
      },
    );

    expect(find.text('Could not load seller profile'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Try again'));
    await settle(tester);

    expect(find.text('Joseph Basilad'), findsOneWidget);
    expect(find.text('Could not load seller profile'), findsNothing);
  });

  testWidgets('Ask Seller and I am Interested are not on the profile', (
    WidgetTester tester,
  ) async {
    await pumpProfile(tester, handler: profileHandler);

    // The public profile is not a second inquiry entry point; the listing
    // actions stay on the listing screen and are not duplicated here.
    expect(find.text('Ask Seller'), findsNothing);
    expect(find.text("I'm Interested"), findsNothing);
  });

  testWidgets('the two tabs split the row and meet the touch height', (
    WidgetTester tester,
  ) async {
    await pumpProfile(tester, handler: profileHandler);

    final Size profileTab = tester.getSize(
      find.byKey(sellerProfileTabProfileKey),
    );
    final Size listingsTab = tester.getSize(
      find.byKey(sellerProfileTabListingsKey),
    );

    expect(profileTab.width, closeTo(listingsTab.width, 0.01));
    expect(profileTab.width, closeTo(200, 1));
    expect(profileTab.height, inInclusiveRange(48, 56));
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(find.byIcon(Icons.grid_view_outlined), findsOneWidget);
  });

  testWidgets('search narrows the server query and starts at page one', (
    WidgetTester tester,
  ) async {
    await pumpProfile(
      tester,
      handler: (RecordedRequest request) async {
        if (request.apiPath == '/marketplace/sellers/3') {
          return sellerProfileResponse();
        }
        if (request.query['search'] == 'angus') {
          return sellerListingsResponse(
            listings: <Map<String, dynamic>>[
              listingJson(id: 14, breed: 'Angus'),
            ],
          );
        }
        return sellerListingsResponse();
      },
    );

    await tester.tap(find.text('Listings'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'angus');
    await settle(tester);

    final List<RecordedRequest> listingRequests = recorded
        .where((RecordedRequest r) => r.apiPath.endsWith('/listings'))
        .toList();
    expect(listingRequests.length, greaterThan(1));
    expect(listingRequests.last.query['search'], 'angus');
    expect(listingRequests.last.query['page'], '1');
    expect(listingRequests.last.query['sort'], 'newest');
    expect(find.text('Angus'), findsOneWidget);
  });

  testWidgets('a category chip filters the server query', (
    WidgetTester tester,
  ) async {
    await pumpProfile(tester, handler: profileHandler);

    await tester.tap(find.text('Listings'));
    await settle(tester);

    final Finder goat = find.byKey(
      const ValueKey<String>('seller-category-goat'),
    );
    await tester.ensureVisible(goat);
    await settle(tester);
    await tester.tap(goat);
    await settle(tester);

    expect(recorded.last.query['livestock_type'], 'goat');
    expect(recorded.last.query['page'], '1');
  });

  testWidgets('the sort menu sends the chosen ordering', (
    WidgetTester tester,
  ) async {
    await pumpProfile(tester, handler: profileHandler);

    await tester.tap(find.text('Listings'));
    await settle(tester);
    expect(find.text('Newest first'), findsOneWidget);

    await tester.tap(find.text('Newest first'));
    await settle(tester);
    await tester.tap(
      find.widgetWithText(
        CheckedPopupMenuItem<SellerListingSort>,
        'Price: Low to High',
      ),
    );
    await settle(tester);

    expect(recorded.last.query['sort'], 'price_asc');
    expect(find.text('Price: Low to High'), findsOneWidget);
  });

  testWidgets('a filtered empty result offers a clear action', (
    WidgetTester tester,
  ) async {
    await pumpProfile(
      tester,
      handler: (RecordedRequest request) async {
        if (request.apiPath == '/marketplace/sellers/3') {
          return sellerProfileResponse();
        }
        if ((request.query['search'] ?? '').isNotEmpty) {
          return sellerListingsResponse(
            listings: <Map<String, dynamic>>[],
            total: 0,
          );
        }
        return sellerListingsResponse();
      },
    );

    await tester.tap(find.text('Listings'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'zzzz');
    await settle(tester);

    expect(find.text('No listings match'), findsOneWidget);
    expect(find.text('Clear filters'), findsOneWidget);

    await tester.tap(find.text('Clear filters'));
    await settle(tester);

    expect(recorded.last.query.containsKey('search'), isFalse);
    expect(recorded.last.query['sort'], 'newest');
    expect(find.byType(ListingCard), findsOneWidget);
  });

  testWidgets('a single listing keeps the two-column card width', (
    WidgetTester tester,
  ) async {
    await pumpProfile(
      tester,
      handler: (RecordedRequest request) => profileHandler(
        request,
        listings: <Map<String, dynamic>>[
          listingJson(id: 12, breed: 'Holstein Friesian'),
        ],
        total: 1,
      ),
    );

    await tester.tap(find.text('Listings'));
    await settle(tester);

    expect(find.byType(ListingCard), findsOneWidget);
    // 400 logical width - 2 × 16 gutter - 12 column gap, halved.
    expect(tester.getSize(find.byType(ListingCard)).width, closeTo(178, 1));
  });

  testWidgets('a long listing name does not overflow the card', (
    WidgetTester tester,
  ) async {
    await pumpProfile(
      tester,
      handler: (RecordedRequest request) => profileHandler(
        request,
        listings: <Map<String, dynamic>>[
          listingJson(
            id: 12,
            breed:
                'Philippine Native Brahman Cross Holstein Friesian Premium Breed',
          ),
        ],
      ),
    );

    await tester.tap(find.text('Listings'));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(ListingCard), findsOneWidget);
  });

  testWidgets('the seller options menu opens the shared report form', (
    WidgetTester tester,
  ) async {
    await pumpProfile(
      tester,
      handler: (RecordedRequest request) => profileHandler(request),
    );

    await tester.tap(find.byTooltip('Seller options'));
    await settle(tester);
    expect(find.text('Report Seller'), findsOneWidget);

    await tester.tap(find.text('Report Seller'));
    await settle(tester);

    expect(find.byType(ReportUserScreen), findsOneWidget);
    expect(find.text('Reported user'), findsOneWidget);
    expect(find.text('Seller'), findsWidgets);
  });
}
