import 'dart:async';

import 'package:agrobenta_mobile/features/marketplace/state/listing_filters.dart';
import 'package:agrobenta_mobile/features/marketplace/state/marketplace_controller.dart';
import 'package:agrobenta_mobile/features/marketplace/state/marketplace_state.dart';
import 'package:agrobenta_mobile/models/listing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/marketplace_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  setUp(() {
    tokenStore = FakeTokenStore('token');
    recorded = <RecordedRequest>[];
  });

  /// A controller over a handler, plus a record of every notification.
  ({MarketplaceController controller, List<MarketplaceState> states}) build(
    Future<http.Response> Function(RecordedRequest request) handler,
  ) {
    final MarketplaceController controller = buildMarketplaceController(
      tokenStore,
      handler,
      recorded: recorded,
    );
    addTearDown(controller.dispose);

    final List<MarketplaceState> states = <MarketplaceState>[controller.state];
    controller.addListener(() => states.add(controller.state));

    return (controller: controller, states: states);
  }

  group('initial load', () {
    test('starts in the initial state with nothing to show', () {
      final MarketplaceController controller = buildMarketplaceController(
        tokenStore,
        (_) async => marketplaceListResponse(),
      );
      addTearDown(controller.dispose);

      expect(controller.state.status, MarketplaceStatus.initial);
      expect(controller.state.listings, isEmpty);
      expect(controller.state.errorMessage, isNull);
    });

    test('loads page one and publishes the listings', () async {
      final (:controller, :states) = build(
        (_) async => marketplaceListResponse(
          listings: <Map<String, dynamic>>[
            listingJson(id: 12),
            listingJson(id: 11),
          ],
          lastPage: 1,
          total: 2,
        ),
      );

      await controller.loadInitial();

      expect(controller.state.status, MarketplaceStatus.ready);
      expect(controller.state.listings, hasLength(2));
      expect(controller.state.isEmpty, isFalse);
      expect(
        states.map((MarketplaceState s) => s.status),
        containsAllInOrder(<MarketplaceStatus>[
          MarketplaceStatus.loading,
          MarketplaceStatus.ready,
        ]),
      );
    });

    test(
      'does not send a second request when called twice back to back',
      () async {
        final (:controller, :states) = build(
          (_) async => marketplaceListResponse(),
        );

        final Future<void> first = controller.loadInitial();
        final Future<void> second = controller.loadInitial();
        await Future.wait<void>(<Future<void>>[first, second]);

        expect(
          recorded,
          hasLength(1),
          reason:
              'a duplicate initial load is the redundant call mobile/AGENTS.md '
              'warns about',
        );
      },
    );
  });

  group('empty results', () {
    test('distinguishes an empty marketplace from a failed request', () async {
      final (:controller, :states) = build(
        (_) async => marketplaceListResponse(
          listings: <Map<String, dynamic>>[],
          total: 0,
        ),
      );

      await controller.loadInitial();

      expect(controller.state.status, MarketplaceStatus.ready);
      expect(controller.state.isEmpty, isTrue);
      expect(controller.state.errorMessage, isNull);
      expect(controller.state.hasActiveQuery, isFalse);
    });

    test('knows the emptiness is caused by a search', () async {
      final (:controller, :states) = build(
        (_) async => marketplaceListResponse(
          listings: <Map<String, dynamic>>[],
          total: 0,
        ),
      );

      await controller.loadInitial();
      controller.updateSearch('nothing matches this');
      await controller.submitSearch();

      expect(controller.state.isEmpty, isTrue);
      expect(controller.state.hasActiveQuery, isTrue);
    });
  });

  group('errors', () {
    test(
      'publishes a displayable message and a retryable failed state',
      () async {
        final (:controller, :states) = build(
          (_) async => throw http.ClientException('connection refused'),
        );

        await controller.loadInitial();

        expect(controller.state.status, MarketplaceStatus.failed);
        expect(controller.state.errorMessage, isNotNull);
        expect(controller.state.errorMessage, isNotEmpty);
      },
    );

    test(
      'surfaces a 401 as a failure without pretending it is a list problem',
      () async {
        final (:controller, :states) = build(
          (_) async => unauthorizedResponse(),
        );

        await controller.loadInitial();

        expect(controller.state.status, MarketplaceStatus.failed);
        expect(
          tokenStore.token,
          isNull,
          reason: 'the client clears it; the app leaves through the auth gate',
        );
      },
    );

    test('retry re-requests page one and can succeed', () async {
      int attempt = 0;
      final (:controller, :states) = build((_) async {
        attempt++;
        if (attempt == 1) {
          throw http.ClientException('connection refused');
        }
        return marketplaceListResponse();
      });

      await controller.loadInitial();
      expect(controller.state.status, MarketplaceStatus.failed);

      await controller.retry();

      expect(controller.state.status, MarketplaceStatus.ready);
      expect(recorded, hasLength(2));
      expect(recorded.last.query['page'], '1');
    });

    test('a malformed response is a failure, not an empty list', () async {
      final (:controller, :states) = build(
        (_) async => http.Response('not json at all', 200),
      );

      await controller.loadInitial();

      expect(controller.state.status, MarketplaceStatus.failed);
      expect(controller.state.isEmpty, isFalse);
    });
  });

  group('search', () {
    test('debounces typing into a single request', () async {
      final (:controller, :states) = build(
        (_) async => marketplaceListResponse(),
      );

      controller.updateSearch('h');
      controller.updateSearch('ho');
      controller.updateSearch('hol');
      controller.updateSearch('hols');
      controller.updateSearch('holstein');

      expect(
        recorded,
        isEmpty,
        reason: 'nothing is sent while the user is still typing',
      );

      await Future<void>.delayed(MarketplaceController.searchDebounce);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(recorded, hasLength(1));
      expect(recorded.single.query['search'], 'holstein');
    });

    test('restarts the debounce on each keystroke', () async {
      final (:controller, :states) = build(
        (_) async => marketplaceListResponse(),
      );

      controller.updateSearch('a');
      // Wait most of the debounce, then keep typing. Without a restart the first
      // timer would have fired on its own and fired a stale search.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      controller.updateSearch('ab');
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(recorded, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(recorded, hasLength(1));
      expect(recorded.single.query['search'], 'ab');
    });

    test('submitSearch skips the remaining debounce', () async {
      final (:controller, :states) = build(
        (_) async => marketplaceListResponse(),
      );

      controller.updateSearch('cattle');
      await controller.submitSearch();

      expect(recorded, hasLength(1));
    });

    test('a search that resolves late cannot overwrite a newer one', () async {
      // The classic race: "h" is sent, then "ho", and the two answers come back
      // in the wrong order. The stale one must be discarded, or the list shows
      // results for "h" under a field containing "ho".
      final List<Completer<http.Response>> pending =
          <Completer<http.Response>>[];

      final (:controller, :states) = build((RecordedRequest request) async {
        final Completer<http.Response> completer = Completer<http.Response>();
        pending.add(completer);
        return completer.future;
      });

      unawaited(controller.loadInitial());
      await pumpEventQueue();
      expect(pending, hasLength(1));

      unawaited(controller.submitSearch());
      await pumpEventQueue();
      expect(pending, hasLength(2));

      // The newer request answers first, then the older one arrives late.
      pending[1].complete(
        marketplaceListResponse(
          listings: <Map<String, dynamic>>[listingJson(id: 99, breed: 'Newer')],
        ),
      );
      await pumpEventQueue();
      pending[0].complete(
        marketplaceListResponse(
          listings: <Map<String, dynamic>>[listingJson(id: 1, breed: 'Older')],
        ),
      );
      await pumpEventQueue();

      expect(
        controller.state.listings.map((Listing l) => l.breed),
        <String>['Newer'],
        reason: 'the stale response must be dropped',
      );
    });

    test('clearing the search re-requests without the term', () async {
      final (:controller, :states) = build(
        (_) async => marketplaceListResponse(),
      );

      await controller.loadInitial();
      controller.updateSearch('cattle');
      await controller.submitSearch();
      expect(recorded.last.query['search'], 'cattle');

      // What the search field's clear button does: empty the text, then commit.
      controller.updateSearch('');
      await controller.submitSearch();

      expect(recorded, hasLength(3));
      expect(recorded.last.query.containsKey('search'), isFalse);
    });
  });

  group('filters', () {
    test(
      'applies livestock type and price bounds as documented query keys',
      () async {
        final (:controller, :states) = build(
          (_) async => marketplaceListResponse(),
        );

        await controller.applyFilters(
          const ListingFilters(
            livestockType: 'Cattle',
            minPrice: '10000',
            maxPrice: '50000',
          ),
        );

        final Map<String, String> query = recorded.single.query;
        expect(query['livestock_type'], 'Cattle');
        expect(query['min_price'], '10000');
        expect(query['max_price'], '50000');
      },
    );

    test('resets to page one when filters change', () async {
      // The pagination the server echoes back has to match the page that was
      // actually asked for, or the "am I on page 2?" assertion is meaningless.
      final (:controller, :states) = build((RecordedRequest request) async {
        final int page = int.parse(request.query['page']!);
        return marketplaceListResponse(
          listings: <Map<String, dynamic>>[listingJson(id: 20 - page)],
          currentPage: page,
          lastPage: 5,
          perPage: 1,
          total: 5,
        );
      });

      await controller.loadInitial();
      await controller.loadMore();
      expect(controller.state.currentPage, 2);

      await controller.applyFilters(
        const ListingFilters(livestockType: 'Goat'),
      );

      expect(controller.state.currentPage, 1);
      expect(recorded.last.query['page'], '1');
    });

    test('re-applying identical filters makes no request', () async {
      final (:controller, :states) = build(
        (_) async => marketplaceListResponse(),
      );

      const ListingFilters filters = ListingFilters(livestockType: 'Cattle');
      await controller.applyFilters(filters);
      expect(recorded, hasLength(1));

      await controller.applyFilters(filters);

      expect(
        recorded,
        hasLength(1),
        reason: 'nothing changed, so there is nothing to ask the server',
      );
    });

    test('clearFilters drops every filter and reloads', () async {
      final (:controller, :states) = build(
        (_) async => marketplaceListResponse(),
      );

      await controller.applyFilters(
        const ListingFilters(livestockType: 'Cattle', maxPrice: '50000'),
      );
      await controller.clearFilters();

      expect(controller.state.filters, ListingFilters.none);
      final Map<String, String> query = recorded.last.query;
      expect(query.containsKey('livestock_type'), isFalse);
      expect(query.containsKey('max_price'), isFalse);
    });

    test('clearing when nothing is applied makes no request', () async {
      final (:controller, :states) = build(
        (_) async => marketplaceListResponse(),
      );

      await controller.loadInitial();
      await controller.clearFilters();

      expect(recorded, hasLength(1));
    });

    test('keeps the search term when filters change', () async {
      final (:controller, :states) = build(
        (_) async => marketplaceListResponse(),
      );

      controller.updateSearch('heifer');
      await controller.submitSearch();
      await controller.applyFilters(const ListingFilters(maxPrice: '90000'));

      expect(recorded.last.query['search'], 'heifer');
      expect(recorded.last.query['max_price'], '90000');
    });

    test(
      'a 422 from a rejected filter is a failure with the server message',
      () async {
        final (:controller, :states) = build(
          (_) async => validationResponse(
            errors: <String, Object>{
              'min_price': <String>['The min price must be a number.'],
            },
          ),
        );

        await controller.applyFilters(const ListingFilters(minPrice: 'abc'));

        expect(controller.state.status, MarketplaceStatus.failed);
        expect(controller.state.errorMessage, isNotEmpty);
      },
    );
  });

  group('pagination', () {
    test('appends the next page to what is already loaded', () async {
      final (:controller, :states) = build((RecordedRequest request) async {
        final int page = int.parse(request.query['page']!);
        return marketplaceListResponse(
          listings: <Map<String, dynamic>>[listingJson(id: 20 - page)],
          currentPage: page,
          lastPage: 3,
          perPage: 1,
          total: 3,
        );
      });

      await controller.loadInitial();
      await controller.loadMore();

      expect(controller.state.listings.map((Listing l) => l.id), <int>[19, 18]);
      expect(controller.state.currentPage, 2);
      expect(controller.state.hasMorePages, isTrue);
    });

    test('does not request past the last page', () async {
      final (:controller, :states) = build(
        (_) async =>
            marketplaceListResponse(currentPage: 1, lastPage: 1, total: 1),
      );

      await controller.loadInitial();
      await controller.loadMore();

      expect(recorded, hasLength(1));
      expect(controller.state.hasMorePages, isFalse);
    });

    test('ignores a second request while a page is in flight', () async {
      final Completer<http.Response> completer = Completer<http.Response>();
      int calls = 0;

      final (:controller, :states) = build((_) async {
        calls++;
        if (calls == 1) {
          return marketplaceListResponse(currentPage: 1, lastPage: 2, total: 2);
        }
        return completer.future;
      });

      await controller.loadInitial();

      unawaited(controller.loadMore());
      await pumpEventQueue();
      unawaited(controller.loadMore());
      unawaited(controller.loadMore());
      await pumpEventQueue();

      expect(
        calls,
        2,
        reason:
            'the end of the list can fire loadMore repeatedly; it must not '
            'fetch page 2 twice',
      );

      completer.complete(
        marketplaceListResponse(currentPage: 2, lastPage: 2, total: 2),
      );
      await pumpEventQueue();
    });

    test('keeps loaded results when a later page fails', () async {
      // The requirement that matters: a page-3 failure must not destroy page 1.
      final (:controller, :states) = build((RecordedRequest request) async {
        if (request.query['page'] == '1') {
          return marketplaceListResponse(
            listings: <Map<String, dynamic>>[listingJson(id: 12)],
            currentPage: 1,
            lastPage: 3,
            perPage: 1,
            total: 3,
          );
        }
        throw http.ClientException('connection refused');
      });

      await controller.loadInitial();
      await controller.loadMore();

      expect(
        controller.state.listings,
        hasLength(1),
        reason: 'already-loaded listings must survive a later failure',
      );
      expect(controller.state.status, MarketplaceStatus.ready);
      expect(controller.state.loadMoreErrorMessage, isNotNull);
      expect(controller.state.errorMessage, isNull);
    });

    test('a later-page failure can be retried', () async {
      int page2Calls = 0;

      final (:controller, :states) = build((RecordedRequest request) async {
        if (request.query['page'] == '1') {
          return marketplaceListResponse(
            listings: <Map<String, dynamic>>[listingJson(id: 12)],
            currentPage: 1,
            lastPage: 2,
            perPage: 1,
            total: 2,
          );
        }
        page2Calls++;
        if (page2Calls == 1) {
          throw http.ClientException('connection refused');
        }
        return marketplaceListResponse(
          listings: <Map<String, dynamic>>[listingJson(id: 11)],
          currentPage: 2,
          lastPage: 2,
          perPage: 1,
          total: 2,
        );
      });

      await controller.loadInitial();
      await controller.loadMore();
      expect(controller.state.loadMoreErrorMessage, isNotNull);

      await controller.loadMore();

      expect(controller.state.loadMoreErrorMessage, isNull);
      expect(controller.state.listings, hasLength(2));
    });

    test('does not load more before the first page has arrived', () async {
      final Completer<http.Response> completer = Completer<http.Response>();
      final (:controller, :states) = build((_) => completer.future);

      unawaited(controller.loadInitial());
      await pumpEventQueue();

      await controller.loadMore();

      expect(
        completer.isCompleted,
        isFalse,
        reason: 'there is nothing to append to yet',
      );
      completer.complete(marketplaceListResponse());
      await pumpEventQueue();
    });
  });

  group('pull to refresh', () {
    test('keeps the loaded listings on screen while re-querying', () async {
      final Completer<http.Response> completer = Completer<http.Response>();
      final ({MarketplaceController controller, List<MarketplaceState> states})
      harness = build((RecordedRequest request) {
        if (recorded.length == 1) {
          return Future<http.Response>.value(marketplaceListResponse());
        }
        return completer.future;
      });

      await harness.controller.loadInitial();
      expect(harness.controller.state.listings, hasLength(1));

      final Future<void> pending = harness.controller.refresh();
      await pumpEventQueue();

      // The list is still there — the buyer is reading it — and the status
      // distinguishes "refreshing" from a blocking first-page load.
      expect(harness.controller.state.status, MarketplaceStatus.refreshing);
      expect(harness.controller.state.listings, hasLength(1));
      expect(harness.controller.state.showsBlockingState, isFalse);

      completer.complete(
        marketplaceListResponse(
          listings: <Map<String, dynamic>>[
            listingJson(id: 2, breed: 'Fresher result'),
          ],
        ),
      );
      await pending;

      expect(harness.controller.state.status, MarketplaceStatus.ready);
      expect(harness.controller.state.listings.single.title, 'Fresher result');
    });

    test('keeps the stale results when the refresh fails', () async {
      int call = 0;
      final ({MarketplaceController controller, List<MarketplaceState> states})
      harness = build((RecordedRequest request) async {
        call++;
        if (call == 1) {
          return marketplaceListResponse();
        }
        return marketplaceListResponse(statusCode: 500);
      });

      await harness.controller.loadInitial();
      await harness.controller.refresh();

      final MarketplaceState state = harness.controller.state;
      expect(state.status, MarketplaceStatus.ready);
      expect(state.listings, hasLength(1), reason: 'still-valid results stay');
      expect(state.errorMessage, isNull, reason: 'not a blocking error');
      expect(state.refreshErrorMessage, isNotNull);
      expect(recorded, hasLength(2));
    });

    test('does not load the next page while a refresh is in flight', () async {
      final Completer<http.Response> completer = Completer<http.Response>();
      int call = 0;
      final ({MarketplaceController controller, List<MarketplaceState> states})
      harness = build((RecordedRequest request) {
        call++;
        if (call == 1) {
          return Future<http.Response>.value(
            marketplaceListResponse(currentPage: 1, lastPage: 2),
          );
        }
        return completer.future;
      });

      await harness.controller.loadInitial();

      final Future<void> pending = harness.controller.refresh();
      await pumpEventQueue();

      // A refresh replaces the whole list, so a page-2 request fired mid-flight
      // would append results to a set that is about to be thrown away.
      await harness.controller.loadMore();
      expect(recorded, hasLength(2), reason: 'no page-2 request');

      completer.complete(marketplaceListResponse());
      await pending;
    });

    test(
      'falls back to a blocking load when there is nothing to keep',
      () async {
        final Completer<http.Response> completer = Completer<http.Response>();
        final ({
          MarketplaceController controller,
          List<MarketplaceState> states,
        })
        harness = build((RecordedRequest request) => completer.future);

        final Future<void> pending = harness.controller.refresh();
        await pumpEventQueue();

        // Nothing was ever loaded, so a refresh is an ordinary first load.
        expect(harness.controller.state.status, MarketplaceStatus.loading);

        completer.complete(marketplaceListResponse());
        await pending;
      },
    );
  });

  group('clearing search and filters together', () {
    test('widens the query in a single request', () async {
      final ({MarketplaceController controller, List<MarketplaceState> states})
      harness = build(
        (RecordedRequest request) async => marketplaceListResponse(),
      );

      await harness.controller.loadInitial();
      await harness.controller.applyFilters(
        const ListingFilters(livestockType: 'cattle', minPrice: '1000'),
      );
      await harness.controller.submitSearch();
      expect(recorded, hasLength(3));

      await harness.controller.clearSearchAndFilters();

      // One request, not one per cleared field.
      expect(recorded, hasLength(4));
      expect(
        recorded.last.query.keys,
        <String>{'page', 'per_page'},
        reason: 'the widened query sends no search or filter',
      );
      expect(harness.controller.state.searchText, isEmpty);
      expect(harness.controller.state.filters, ListingFilters.none);
    });

    test('is a no-op when there is nothing to clear', () async {
      final ({MarketplaceController controller, List<MarketplaceState> states})
      harness = build(
        (RecordedRequest request) async => marketplaceListResponse(),
      );

      await harness.controller.loadInitial();
      await harness.controller.clearSearchAndFilters();

      expect(recorded, hasLength(1));
    });
  });

  group('lifecycle', () {
    test('does not publish after dispose', () async {
      final Completer<http.Response> completer = Completer<http.Response>();
      final MarketplaceController controller = buildMarketplaceController(
        tokenStore,
        (_) => completer.future,
      );

      unawaited(controller.loadInitial());
      await pumpEventQueue();

      controller.dispose();
      completer.complete(marketplaceListResponse());
      await pumpEventQueue();

      expect(controller.state.status, MarketplaceStatus.loading);
    });

    test('cancels a pending debounce on dispose', () async {
      // Built without the `build` helper, which registers its own teardown
      // dispose — this test disposes early on purpose.
      final MarketplaceController controller = buildMarketplaceController(
        tokenStore,
        (_) async => marketplaceListResponse(),
        recorded: recorded,
      );

      controller.updateSearch('cattle');
      controller.dispose();
      await Future<void>.delayed(MarketplaceController.searchDebounce);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(recorded, isEmpty);
    });
  });
}
