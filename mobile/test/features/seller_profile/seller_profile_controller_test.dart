import 'dart:convert';

import 'package:agrobenta_mobile/features/seller_profile/state/seller_listing_filters.dart';
import 'package:agrobenta_mobile/features/seller_profile/state/seller_profile_controller.dart';
import 'package:agrobenta_mobile/features/seller_profile/state/seller_profile_state.dart';
import 'package:agrobenta_mobile/repositories/marketplace_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/marketplace_fakes.dart';
import '../../support/seller_profile_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  setUp(() {
    tokenStore = FakeTokenStore('valid-mobile-token');
    recorded = <RecordedRequest>[];
  });

  SellerProfileController buildController(
    Future<http.Response> Function(RecordedRequest request) handler,
  ) {
    final MarketplaceRepository repository = buildMarketplaceRepository(
      tokenStore,
      handler,
      recorded: recorded,
    );
    final SellerProfileController controller = SellerProfileController(
      repository,
      3,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  /// A handler that answers the profile, then the seller's listings.
  Future<http.Response> happyPath(
    RecordedRequest request, {
    int activeListingsCount = 2,
  }) async {
    if (request.apiPath == '/marketplace/sellers/3') {
      return sellerProfileResponse(
        profile: sellerProfileJson(activeListingsCount: activeListingsCount),
      );
    }
    if (request.apiPath == '/marketplace/sellers/3/listings') {
      return sellerListingsResponse(
        listings: <Map<String, dynamic>>[listingJson(id: 12)],
        total: 1,
      );
    }
    return sellerNotFoundResponse();
  }

  group('SellerProfileController.load', () {
    test('loads the public profile from the marketplace endpoint', () async {
      final SellerProfileController controller = buildController(happyPath);

      await controller.load();

      expect(recorded.single.apiPath, '/marketplace/sellers/3');
      expect(controller.state.status, SellerProfileStatus.ready);
      expect(controller.state.profile?.name, 'Joseph Basilad');
      expect(controller.state.profile?.isVerified, isTrue);
      expect(controller.state.profile?.activeListingsCount, 2);
    });

    test('a missing or non-public seller becomes unavailable', () async {
      final SellerProfileController controller = buildController(
        (_) async => sellerNotFoundResponse(),
      );

      await controller.load();

      expect(controller.state.status, SellerProfileStatus.unavailable);
      expect(controller.state.profile, isNull);
    });

    test('a server failure becomes a retryable failed state', () async {
      final SellerProfileController controller = buildController(
        (_) async => http.Response(
          jsonEncode(<String, Object>{
            'success': false,
            'message': 'Server exploded.',
          }),
          500,
          headers: const <String, String>{'content-type': 'application/json'},
        ),
      );

      await controller.load();

      expect(controller.state.status, SellerProfileStatus.failed);
      expect(controller.state.errorMessage, isNotNull);
    });

    test('does not request twice while the first load is in flight', () async {
      final SellerProfileController controller = buildController(happyPath);

      await Future.wait(<Future<void>>[controller.load(), controller.load()]);

      expect(recorded, hasLength(1));
    });
  });

  group('SellerProfileController.listings', () {
    test('loads the listings page lazily when the tab is opened', () async {
      final SellerProfileController controller = buildController(happyPath);
      await controller.load();

      // Opening the profile does not fetch listings.
      expect(
        recorded.where((RecordedRequest r) => r.apiPath.endsWith('/listings')),
        isEmpty,
      );
      expect(controller.state.listingsStatus, SellerListingsStatus.initial);

      await controller.selectTab(SellerProfileTab.listings);

      expect(controller.state.listingsStatus, SellerListingsStatus.ready);
      expect(controller.state.listings.map((listing) => listing.id), <int>[12]);
      expect(recorded.last.apiPath, '/marketplace/sellers/3/listings');
    });

    test('does not re-request listings when the tab is reopened', () async {
      final SellerProfileController controller = buildController(happyPath);
      await controller.load();
      await controller.selectTab(SellerProfileTab.listings);

      await controller.selectTab(SellerProfileTab.profile);
      await controller.selectTab(SellerProfileTab.listings);

      expect(
        recorded.where((RecordedRequest r) => r.apiPath.endsWith('/listings')),
        hasLength(1),
      );
    });

    test('appends the next page and keeps a total order', () async {
      final SellerProfileController controller = buildController((
        RecordedRequest request,
      ) async {
        if (request.apiPath == '/marketplace/sellers/3') {
          return sellerProfileResponse();
        }
        if (request.query['page'] == '2') {
          return sellerListingsResponse(
            listings: <Map<String, dynamic>>[listingJson(id: 11)],
            currentPage: 2,
            lastPage: 2,
            total: 2,
          );
        }
        return sellerListingsResponse(
          listings: <Map<String, dynamic>>[listingJson(id: 12)],
          currentPage: 1,
          lastPage: 2,
          total: 2,
        );
      });
      await controller.load();
      await controller.selectTab(SellerProfileTab.listings);

      await controller.loadMoreListings();

      expect(controller.state.listings.map((listing) => listing.id), <int>[
        12,
        11,
      ]);
      expect(controller.state.pagination?.currentPage, 2);
      expect(controller.state.hasMoreListings, isFalse);
    });

    test('a failed later page keeps the loaded results', () async {
      final SellerProfileController controller = buildController((
        RecordedRequest request,
      ) async {
        if (request.apiPath == '/marketplace/sellers/3') {
          return sellerProfileResponse();
        }
        if (request.query['page'] == '2') {
          return http.Response(
            jsonEncode(<String, Object>{
              'success': false,
              'message': 'Server exploded.',
            }),
            500,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        return sellerListingsResponse(
          listings: <Map<String, dynamic>>[listingJson(id: 12)],
          currentPage: 1,
          lastPage: 2,
          total: 2,
        );
      });
      await controller.load();
      await controller.selectTab(SellerProfileTab.listings);

      await controller.loadMoreListings();

      expect(controller.state.listingsStatus, SellerListingsStatus.ready);
      expect(controller.state.listings, hasLength(1));
      expect(controller.state.listingsLoadMoreErrorMessage, isNotNull);
    });

    test('a first-page failure is retryable', () async {
      var fail = true;
      final SellerProfileController controller = buildController((
        RecordedRequest request,
      ) async {
        if (request.apiPath == '/marketplace/sellers/3') {
          return sellerProfileResponse();
        }
        if (fail) {
          return http.Response(
            jsonEncode(<String, Object>{
              'success': false,
              'message': 'Server exploded.',
            }),
            500,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        return sellerListingsResponse();
      });
      await controller.load();
      await controller.selectTab(SellerProfileTab.listings);

      expect(controller.state.listingsStatus, SellerListingsStatus.failed);

      fail = false;
      await controller.retryListings();

      expect(controller.state.listingsStatus, SellerListingsStatus.ready);
      expect(controller.state.listings, isNotEmpty);
    });

    test('a 404 on the listings page becomes unavailable', () async {
      final SellerProfileController controller = buildController((
        RecordedRequest request,
      ) async {
        if (request.apiPath == '/marketplace/sellers/3') {
          return sellerProfileResponse();
        }
        return sellerNotFoundResponse();
      });
      await controller.load();

      await controller.selectTab(SellerProfileTab.listings);

      expect(controller.state.listingsStatus, SellerListingsStatus.unavailable);
    });

    test(
      'filters are forwarded on the first page and every later page',
      () async {
        final SellerProfileController controller = buildController((
          RecordedRequest request,
        ) async {
          if (request.apiPath == '/marketplace/sellers/3') {
            return sellerProfileResponse();
          }
          if (request.query['page'] == '2') {
            return sellerListingsResponse(
              listings: <Map<String, dynamic>>[listingJson(id: 11)],
              currentPage: 2,
              lastPage: 2,
              total: 2,
            );
          }
          return sellerListingsResponse(
            listings: <Map<String, dynamic>>[listingJson(id: 12)],
            currentPage: 1,
            lastPage: 2,
            total: 2,
          );
        });
        await controller.load();
        await controller.selectTab(SellerProfileTab.listings);

        await controller.selectCategory('goat');
        await controller.selectSort(SellerListingSort.priceLowToHigh);
        controller.updateSearch('angus');
        await controller.submitSearch();

        final RecordedRequest firstPage = recorded.last;
        expect(firstPage.query['search'], 'angus');
        expect(firstPage.query['livestock_type'], 'goat');
        expect(firstPage.query['sort'], 'price_asc');
        expect(firstPage.query['page'], '1');

        await controller.loadMoreListings();

        expect(recorded.last.query['search'], 'angus');
        expect(recorded.last.query['livestock_type'], 'goat');
        expect(recorded.last.query['sort'], 'price_asc');
        expect(recorded.last.query['page'], '2');
      },
    );

    test('clearing filters returns to the default query', () async {
      final SellerProfileController controller = buildController(happyPath);
      await controller.load();
      await controller.selectTab(SellerProfileTab.listings);

      await controller.selectCategory('goat');
      await controller.selectSort(SellerListingSort.oldest);
      controller.updateSearch('angus');
      await controller.submitSearch();

      await controller.clearListingFilters();

      expect(controller.state.searchText, isEmpty);
      expect(controller.state.livestockType, isEmpty);
      expect(controller.state.sort, SellerListingSort.newest);
      expect(controller.state.hasActiveListingFilters, isFalse);
      expect(recorded.last.query.containsKey('search'), isFalse);
      expect(recorded.last.query.containsKey('livestock_type'), isFalse);
      expect(recorded.last.query['sort'], 'newest');
      expect(recorded.last.query['page'], '1');
    });
  });

  group('SellerProfileController.refresh', () {
    test('keeps valid data when the refresh fails', () async {
      var fail = false;
      final SellerProfileController controller = buildController((
        RecordedRequest request,
      ) async {
        if (request.apiPath == '/marketplace/sellers/3') {
          return fail
              ? http.Response(
                  jsonEncode(<String, Object>{
                    'success': false,
                    'message': 'Server exploded.',
                  }),
                  500,
                  headers: const <String, String>{
                    'content-type': 'application/json',
                  },
                )
              : sellerProfileResponse();
        }
        return sellerListingsResponse();
      });
      await controller.load();
      await controller.selectTab(SellerProfileTab.listings);

      fail = true;
      await controller.refresh();

      expect(controller.state.status, SellerProfileStatus.ready);
      expect(controller.state.profile, isNotNull);
      expect(controller.state.refreshErrorMessage, isNotNull);
      expect(controller.state.listings, isNotEmpty);
    });

    test('a 404 on refresh replaces the screen with unavailable', () async {
      var gone = false;
      final SellerProfileController controller = buildController((
        RecordedRequest request,
      ) async {
        if (request.apiPath == '/marketplace/sellers/3') {
          return gone ? sellerNotFoundResponse() : sellerProfileResponse();
        }
        return sellerListingsResponse();
      });
      await controller.load();

      gone = true;
      await controller.refresh();

      expect(controller.state.status, SellerProfileStatus.unavailable);
    });

    test('refreshes the listings page too when it has been opened', () async {
      final SellerProfileController controller = buildController((
        RecordedRequest request,
      ) async {
        if (request.apiPath == '/marketplace/sellers/3') {
          return sellerProfileResponse();
        }
        return sellerListingsResponse();
      });
      await controller.load();
      await controller.selectTab(SellerProfileTab.listings);
      final int listingsRequests = recorded
          .where((RecordedRequest r) => r.apiPath.endsWith('/listings'))
          .length;

      await controller.refresh();

      expect(
        recorded.where((RecordedRequest r) => r.apiPath.endsWith('/listings')),
        hasLength(listingsRequests + 1),
      );
    });
  });
}
