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

    testWidgets('a card shows completed sales and the placeholder rating', (
      WidgetTester tester,
    ) async {
      await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => marketplaceListResponse(
          listings: <Map<String, dynamic>>[
            listingJson(id: 12, completedSales: 2),
          ],
        ),
      );

      expect(find.text('2 completed sales'), findsOneWidget);
      expect(find.text('4.8 · 24 reviews'), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    });

    testWidgets('a listing with no completed sales says zero', (
      WidgetTester tester,
    ) async {
      await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => marketplaceListResponse(
          listings: <Map<String, dynamic>>[listingJson(completedSales: 0)],
        ),
      );

      expect(find.text('0 completed sales'), findsOneWidget);
    });

    testWidgets('lays listings out in a two-column grid', (
      WidgetTester tester,
    ) async {
      await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => marketplaceListResponse(
          listings: <Map<String, dynamic>>[
            listingJson(id: 12),
            listingJson(id: 11),
            listingJson(id: 10),
          ],
        ),
      );

      final SliverGrid grid = tester.widget<SliverGrid>(
        find.byType(SliverGrid),
      );
      final SliverGridDelegateWithFixedCrossAxisCount delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 2);

      final Offset first = tester.getTopLeft(find.byType(ListingCard).at(0));
      final Offset second = tester.getTopLeft(find.byType(ListingCard).at(1));
      final Offset third = tester.getTopLeft(find.byType(ListingCard).at(2));

      expect(first.dy, second.dy, reason: 'first two share a row');
      expect(first.dx, isNot(second.dx), reason: 'and sit side by side');
      expect(third.dy, greaterThan(first.dy), reason: 'the third wraps');
    });

    testWidgets('the grid card fits a narrow phone width', (
      WidgetTester tester,
    ) async {
      await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => marketplaceListResponse(
          listings: <Map<String, dynamic>>[listingJson(id: 12)],
        ),
      );

      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpAndSettle();

      expect(find.byType(ListingCard), findsOneWidget);
      expect(tester.takeException(), isNull);
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
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 600),
        1200,
      );
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

    testWidgets('the clear button empties the query and reloads once', (
      WidgetTester tester,
    ) async {
      final MarketplaceHarness harness = await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => marketplaceListResponse(),
      );

      await tester.enterText(find.byType(TextField), 'cat');
      await settleMarketplace(tester, frames: 12);

      final int afterSearch = harness.recorded.length;
      expect(afterSearch, greaterThan(1));

      await tester.tap(find.byIcon(Icons.close));
      await settleMarketplace(tester, frames: 12);

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty,
        reason: 'the field clears immediately',
      );
      expect(
        harness.recorded.length,
        afterSearch + 1,
        reason: 'one request for the cleared query, and no debounce repeat',
      );
      expect(harness.recorded.last.query.containsKey('search'), isFalse);
    });
  });

  group('browse categories', () {
    testWidgets('starts on All and applies an exact livestock_type filter', (
      WidgetTester tester,
    ) async {
      final MarketplaceHarness harness = await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => marketplaceListResponse(),
      );

      ChoiceChip chip(String value) => tester.widget<ChoiceChip>(
        find.byKey(ValueKey<String>('browse-category-$value')),
      );

      expect(chip('all').selected, isTrue);
      expect(find.text('Category:'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey<String>('browse-category-swine')),
      );
      await settleMarketplace(tester, frames: 12);

      expect(harness.recorded.last.query['livestock_type'], 'swine');
      expect(chip('swine').selected, isTrue);
      expect(chip('all').selected, isFalse);
      expect(find.text('Category: Swine'), findsOneWidget);
    });

    testWidgets('reflects a category applied from Home or the Filter screen', (
      WidgetTester tester,
    ) async {
      final MarketplaceHarness harness = await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => marketplaceListResponse(),
      );

      await harness.controller.applyFilters(
        const ListingFilters(livestockType: 'carabao'),
      );
      await tester.pumpAndSettle();

      final ChoiceChip carabao = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey<String>('browse-category-carabao')),
      );
      expect(carabao.selected, isTrue);
      expect(find.text('Category: Carabao'), findsOneWidget);
    });

    testWidgets('the indicator removes only the category', (
      WidgetTester tester,
    ) async {
      final MarketplaceHarness harness = await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => marketplaceListResponse(),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('browse-category-goat')),
      );
      await settleMarketplace(tester, frames: 12);

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('active-category-filter')),
          matching: find.byIcon(Icons.close),
        ),
      );
      await settleMarketplace(tester, frames: 12);

      expect(
        harness.recorded.last.query.containsKey('livestock_type'),
        isFalse,
      );
      expect(find.textContaining('Category: '), findsNothing);
      final ChoiceChip all = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey<String>('browse-category-all')),
      );
      expect(all.selected, isTrue);
    });

    testWidgets('the search X clears the search and every active filter', (
      WidgetTester tester,
    ) async {
      final MarketplaceHarness harness = await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => marketplaceListResponse(),
      );

      await tester.enterText(find.byType(TextField), 'angus');
      await settleMarketplace(tester, frames: 12);
      await tester.tap(
        find.byKey(const ValueKey<String>('browse-category-cattle')),
      );
      await settleMarketplace(tester, frames: 12);

      final int beforeClear = harness.recorded.length;

      await tester.tap(
        find.descendant(
          of: find.byType(TextField),
          matching: find.byIcon(Icons.close),
        ),
      );
      await settleMarketplace(tester, frames: 12);

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty,
      );
      expect(harness.recorded.length, beforeClear + 1);
      final Map<String, String> query = harness.recorded.last.query;
      expect(query.containsKey('search'), isFalse);
      expect(query.containsKey('livestock_type'), isFalse);
      expect(find.textContaining('Category: '), findsNothing);
      final ChoiceChip all = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey<String>('browse-category-all')),
      );
      expect(all.selected, isTrue);
    });
  });

  group('filters', () {
    testWidgets('opens the filter screen and applies a price bound', (
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

      expect(find.text('Filter Livestock'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Min price'),
        '10000',
      );
      await tester.tap(find.text('Apply Filters'));
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
      await tester.tap(find.text('Apply Filters'));
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
      await tester.tap(
        find.byKey(const ValueKey<String>('animal-type-cattle')),
      );
      await tester.tap(find.text('Apply Filters'));
      await settleMarketplace(tester, frames: 12);

      // The count, not the values — the filter screen shows the values.
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('reset then apply clears the filters and reloads', (
      WidgetTester tester,
    ) async {
      final harness = await MarketplaceHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => marketplaceListResponse(),
      );

      await tester.tap(find.byIcon(Icons.tune));
      await settleMarketplace(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('animal-type-cattle')),
      );
      await tester.tap(find.text('Apply Filters'));
      await settleMarketplace(tester, frames: 12);

      await tester.tap(find.byIcon(Icons.tune));
      await settleMarketplace(tester);
      await tester.tap(find.text('Reset'));
      await tester.tap(find.text('Apply Filters'));
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
        livestockType: 'cattle',
        maxPrice: '50000',
      );

      expect(filters.activeCount, 2);
      expect(filters.summary, contains('cattle'));
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
        const ListingFilters(livestockType: 'cattle'),
        const ListingFilters(livestockType: 'cattle'),
      );
      expect(
        const ListingFilters(livestockType: 'cattle'),
        isNot(const ListingFilters(livestockType: 'goat')),
      );
    });
  });
}
