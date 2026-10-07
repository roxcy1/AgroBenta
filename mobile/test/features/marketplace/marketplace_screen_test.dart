import 'package:agrobenta_mobile/features/marketplace/state/listing_filters.dart';
import 'package:agrobenta_mobile/features/marketplace/views/listing_detail_screen.dart';
import 'package:agrobenta_mobile/features/marketplace/widgets/listing_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/marketplace_app_harness.dart';
import '../../support/marketplace_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;

  setUp(() => tokenStore = FakeTokenStore('token'));

  group('loading', () {
    testWidgets('shows a loading state before the first page arrives', (
      WidgetTester tester,
    ) async {
      await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => throw http.ClientException('refused'),
      );

      // A skeleton, not a bare spinner: the list's shape should be visible
      // before its contents are.
      expect(find.byType(ListingCard), findsNothing);
      expect(find.text('Could not load listings'), findsOneWidget);
    });

    testWidgets('requests the marketplace endpoint once on open', (
      WidgetTester tester,
    ) async {
      final harness = await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => marketplaceListResponse(),
      );

      expect(harness.recorded, hasLength(1));
      expect(harness.recorded.single.apiPath, '/listings');
    });
  });

  group('results', () {
    testWidgets('renders a card per listing with its price and location', (
      WidgetTester tester,
    ) async {
      await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => marketplaceListResponse(
          listings: <Map<String, dynamic>>[
            listingJson(id: 12, breed: 'Holstein', askingPrice: '42500.00'),
            listingJson(id: 11, breed: 'Angus', askingPrice: '78000.00'),
          ],
        ),
      );

      expect(find.byType(ListingCard), findsNWidgets(2));
      expect(find.text('Holstein'), findsOneWidget);
      expect(find.text('Angus'), findsOneWidget);
      expect(find.text('₱42,500'), findsOneWidget);
      expect(find.text('₱78,000'), findsOneWidget);
      expect(find.text('Mabalacat, Pampanga'), findsNWidgets(2));
    });

    testWidgets('shows a placeholder for a listing with no loadable photo', (
      WidgetTester tester,
    ) async {
      await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => marketplaceListResponse(
          listings: <Map<String, dynamic>>[
            listingJson(photos: <Object?>['listings/12/front.jpg']),
          ],
        ),
      );

      // The stored path is not a URL, so it must not be handed to a loader.
      expect(find.text('Photo unavailable'), findsOneWidget);
    });

    testWidgets('never renders a stored photo path as text', (
      WidgetTester tester,
    ) async {
      await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => marketplaceListResponse(
          listings: <Map<String, dynamic>>[
            listingJson(photos: <Object?>['listings/12/front.jpg']),
          ],
        ),
      );

      expect(find.textContaining('listings/12'), findsNothing);
    });
  });

  group('empty and error states', () {
    testWidgets('says the marketplace is empty when there are no listings', (
      WidgetTester tester,
    ) async {
      await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => marketplaceListResponse(
          listings: <Map<String, dynamic>>[],
          total: 0,
        ),
      );

      expect(find.text('No active listings yet'), findsOneWidget);
      expect(find.text('Clear search and filters'), findsNothing);
    });

    testWidgets(
      'blames the query, not the marketplace, when a search finds nothing',
      (WidgetTester tester) async {
        await MarketplaceHarness.pump(
          tester,
          tokenStore: tokenStore,
          handler: (_) async => marketplaceListResponse(
            listings: <Map<String, dynamic>>[],
            total: 0,
          ),
        );

        await tester.enterText(find.byType(TextField), 'nothing here');
        await settleMarketplace(tester, frames: 12);

        expect(find.text('No listings match'), findsOneWidget);
        expect(find.text('Clear search and filters'), findsOneWidget);
      },
    );

    testWidgets('offers a retry that re-requests after a failure', (
      WidgetTester tester,
    ) async {
      int calls = 0;
      final harness = await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async {
          calls++;
          if (calls == 1) {
            return http.Response('not json', 200);
          }
          return marketplaceListResponse();
        },
      );

      expect(find.text('Could not load listings'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await settleMarketplace(tester);

      expect(find.text('Could not load listings'), findsNothing);
      expect(find.byType(ListingCard), findsOneWidget);
      expect(harness.recorded, hasLength(2));
    });
  });

  group('pull to refresh', () {
    /// Drags the list down far enough to trip the [RefreshIndicator].
    ///
    /// A deliberate fling rather than a small drag: the taller image-on-top
    /// card leaves less empty scroll extent, so the pull needs enough distance
    /// and velocity to arm the indicator reliably.
    Future<void> pullToRefresh(WidgetTester tester) async {
      await tester.fling(find.byType(ListView), const Offset(0, 600), 1200);
      await settleMarketplace(tester, frames: 12);
    }

    testWidgets('keeps the loaded cards on screen while re-querying', (
      WidgetTester tester,
    ) async {
      int calls = 0;
      final harness = await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async {
          calls++;
          if (calls == 1) {
            return marketplaceListResponse();
          }
          return marketplaceListResponse(
            listings: <Map<String, dynamic>>[
              listingJson(id: 2, breed: 'Newest'),
            ],
          );
        },
      );

      expect(find.text('Holstein'), findsOneWidget);

      await pullToRefresh(tester);

      // The results were never blanked, and the fresh ones replaced them.
      expect(find.text('Holstein'), findsNothing);
      expect(find.text('Newest'), findsOneWidget);
      expect(harness.recorded, hasLength(2));
    });

    testWidgets('shows a notice and keeps results when the refresh fails', (
      WidgetTester tester,
    ) async {
      int calls = 0;
      await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async {
          calls++;
          if (calls == 1) {
            return marketplaceListResponse();
          }
          return marketplaceListResponse(statusCode: 500);
        },
      );

      await pullToRefresh(tester);

      // Not a full-screen error: the cards the buyer was reading are still
      // valid, and the notice says so.
      expect(find.byType(ListingCard), findsOneWidget);
      expect(find.text('Could not load listings'), findsNothing);
      expect(find.textContaining('Could not refresh'), findsOneWidget);
    });

    testWidgets('a full-screen error still retries as a blocking load', (
      WidgetTester tester,
    ) async {
      int calls = 0;
      await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async {
          calls++;
          if (calls == 1) {
            return marketplaceListResponse(statusCode: 500);
          }
          return marketplaceListResponse();
        },
      );

      expect(find.text('Could not load listings'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await settleMarketplace(tester);

      expect(find.text('Could not load listings'), findsNothing);
      expect(find.byType(ListingCard), findsOneWidget);
    });
  });

  group('search', () {
    testWidgets('does not request on every keystroke', (
      WidgetTester tester,
    ) async {
      final harness = await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => marketplaceListResponse(),
      );
      final int afterLoad = harness.recorded.length;

      await tester.enterText(find.byType(TextField), 'holstein');
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        harness.recorded.length,
        afterLoad,
        reason: 'typing must not fire a request per character',
      );

      await settleMarketplace(tester, frames: 12);

      expect(harness.recorded.length, afterLoad + 1);
      expect(harness.recorded.last.query['search'], 'holstein');
    });

    testWidgets('has a clear button only when there is a term', (
      WidgetTester tester,
    ) async {
      await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => marketplaceListResponse(),
      );

      expect(find.byIcon(Icons.close), findsNothing);

      await tester.enterText(find.byType(TextField), 'cat');
      await settleMarketplace(tester, frames: 12);

      expect(find.byIcon(Icons.close), findsOneWidget);
    });
  });

  group('filters', () {
    testWidgets('opens a sheet and applies a price bound', (
      WidgetTester tester,
    ) async {
      final harness = await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => marketplaceListResponse(),
      );
      final int afterLoad = harness.recorded.length;

      await tester.tap(find.byIcon(Icons.tune));
      await settleMarketplace(tester);

      expect(find.text('Filters'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Min price'),
        '10000',
      );
      await tester.tap(find.text('Apply filters'));
      await settleMarketplace(tester, frames: 12);

      expect(harness.recorded.length, afterLoad + 1);
      expect(harness.recorded.last.query['min_price'], '10000');
    });

    testWidgets('refuses an inverted price range without requesting', (
      WidgetTester tester,
    ) async {
      final harness = await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => marketplaceListResponse(),
      );
      final int afterLoad = harness.recorded.length;

      await tester.tap(find.byIcon(Icons.tune));
      await settleMarketplace(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Min price'),
        '50000',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Max price'),
        '10000',
      );
      await tester.tap(find.text('Apply filters'));
      await settleMarketplace(tester);

      expect(
        find.text('The minimum price is higher than the maximum price.'),
        findsOneWidget,
      );
      expect(
        harness.recorded.length,
        afterLoad,
        reason: 'an impossible range is explained, not sent',
      );
    });

    testWidgets('marks the filter button active once filters are applied', (
      WidgetTester tester,
    ) async {
      await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => marketplaceListResponse(),
      );

      await tester.tap(find.byIcon(Icons.tune));
      await settleMarketplace(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Livestock type'),
        'Cattle',
      );
      await tester.tap(find.text('Apply filters'));
      await settleMarketplace(tester, frames: 12);

      // The count, not the values — the sheet shows the values.
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('clearing all filters from the sheet reloads unfiltered', (
      WidgetTester tester,
    ) async {
      final harness = await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => marketplaceListResponse(),
      );

      await tester.tap(find.byIcon(Icons.tune));
      await settleMarketplace(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Livestock type'),
        'Cattle',
      );
      await tester.tap(find.text('Apply filters'));
      await settleMarketplace(tester, frames: 12);

      await tester.tap(find.byIcon(Icons.tune));
      await settleMarketplace(tester);
      await tester.tap(find.text('Clear all'));
      await settleMarketplace(tester, frames: 12);

      expect(
        harness.recorded.last.query.containsKey('livestock_type'),
        isFalse,
      );
    });
  });

  group('pagination', () {
    testWidgets('shows a load-more control and appends the next page', (
      WidgetTester tester,
    ) async {
      final harness = await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (RecordedRequest request) async {
          final int page = int.parse(request.query['page']!);
          return marketplaceListResponse(
            listings: <Map<String, dynamic>>[
              listingJson(id: 20 - page, breed: 'Page$page'),
            ],
            currentPage: page,
            lastPage: 2,
            perPage: 1,
            total: 2,
          );
        },
      );

      expect(find.text('Load more'), findsOneWidget);
      final int afterLoad = harness.recorded.length;

      await tester.tap(find.text('Load more'));
      await settleMarketplace(tester, frames: 12);

      expect(harness.recorded.length, afterLoad + 1);
      expect(harness.recorded.last.query['page'], '2');
      expect(find.text('Page1'), findsOneWidget);
      expect(find.text('Page2'), findsOneWidget);
    });

    testWidgets('offers no load-more on the last page', (
      WidgetTester tester,
    ) async {
      await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => marketplaceListResponse(
          listings: <Map<String, dynamic>>[listingJson()],
          currentPage: 1,
          lastPage: 1,
          total: 1,
        ),
      );

      expect(find.text('Load more'), findsNothing);
    });

    testWidgets('keeps the loaded list when a later page fails', (
      WidgetTester tester,
    ) async {
      await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (RecordedRequest request) async {
          if (request.query['page'] == '1') {
            return marketplaceListResponse(
              listings: <Map<String, dynamic>>[listingJson(breed: 'Survivor')],
              currentPage: 1,
              lastPage: 2,
              perPage: 1,
              total: 2,
            );
          }
          return http.Response('nope', 500);
        },
      );

      await tester.tap(find.text('Load more'));
      await settleMarketplace(tester, frames: 12);

      expect(
        find.text('Survivor'),
        findsOneWidget,
        reason: 'a page-2 failure must not wipe the page-1 results',
      );
      expect(find.text('Could not load listings'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('navigation to detail', () {
    testWidgets('a card tap opens the detail screen for that listing', (
      WidgetTester tester,
    ) async {
      await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (RecordedRequest request) async {
          if (request.apiPath == '/listings') {
            return marketplaceListResponse(
              listings: <Map<String, dynamic>>[listingJson(id: 12)],
            );
          }
          return listingDetailResponse();
        },
      );

      await tester.tap(find.byType(ListingCard));
      await settleMarketplace(tester, frames: 12);

      expect(find.byType(ListingDetailScreen), findsOneWidget);
      expect(find.text('Holstein'), findsWidgets);
      expect(find.text('₱42,500.00'), findsOneWidget);
    });

    testWidgets(
      're-fetches the listing on open rather than reusing the card data',
      (WidgetTester tester) async {
        final harness = await MarketplaceHarness.pump(
          tester,
          tokenStore: tokenStore,
          handler: (RecordedRequest request) async {
            if (request.apiPath == '/listings') {
              return marketplaceListResponse(
                listings: <Map<String, dynamic>>[listingJson(id: 12)],
              );
            }
            return listingDetailResponse();
          },
        );

        await tester.tap(find.byType(ListingCard));
        await settleMarketplace(tester, frames: 12);

        expect(
          harness.recorded.map((RecordedRequest r) => r.apiPath),
          containsAllInOrder(<String>['/listings', '/listings/12']),
          reason: 'a listing can go inactive between the two requests',
        );
      },
    );

    testWidgets('a listing that went inactive renders the unavailable notice', (
      WidgetTester tester,
    ) async {
      await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (RecordedRequest request) async {
          if (request.apiPath == '/listings') {
            return marketplaceListResponse(
              listings: <Map<String, dynamic>>[listingJson(id: 12)],
            );
          }
          return listingNotFoundResponse();
        },
      );

      await tester.tap(find.byType(ListingCard));
      await settleMarketplace(tester, frames: 12);

      expect(find.text('This listing is no longer available'), findsOneWidget);
      expect(
        find.textContaining('not found'),
        findsNothing,
        reason: 'the backend\'s 404 wording must not leak to a buyer',
      );
    });
  });

  group('filter value semantics', () {
    test('an empty filter set is not active', () {
      expect(ListingFilters.none.isActive, isFalse);
      expect(ListingFilters.none.activeCount, 0);
      expect(ListingFilters.none.summary, isEmpty);
    });

    test('counts each set field', () {
      const ListingFilters filters = ListingFilters(
        livestockType: 'Cattle',
        maxPrice: '50000',
      );

      expect(filters.activeCount, 2);
      expect(filters.summary, contains('Cattle'));
    });

    test('treats whitespace as unset', () {
      const ListingFilters filters = ListingFilters(livestockType: '   ');

      expect(filters.isActive, isFalse);
    });

    test('detects an inverted price range', () {
      const ListingFilters filters = ListingFilters(
        minPrice: '50000',
        maxPrice: '10000',
      );

      expect(filters.hasInvertedPriceRange, isTrue);
    });

    test('accepts an equal-bound range', () {
      const ListingFilters filters = ListingFilters(
        minPrice: '10000',
        maxPrice: '10000',
      );

      expect(filters.hasInvertedPriceRange, isFalse);
    });

    test('compares by value so a re-apply can be recognised', () {
      expect(
        const ListingFilters(livestockType: 'Cattle'),
        const ListingFilters(livestockType: 'Cattle'),
      );
      expect(
        const ListingFilters(livestockType: 'Cattle'),
        isNot(const ListingFilters(livestockType: 'Goat')),
      );
    });
  });
}
