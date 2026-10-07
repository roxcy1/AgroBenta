import 'dart:async';

import 'package:agrobenta_mobile/features/marketplace/state/listing_detail_controller.dart';
import 'package:agrobenta_mobile/features/marketplace/state/listing_detail_state.dart';
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

  ListingDetailController build(
    Future<http.Response> Function(RecordedRequest request) handler,
  ) {
    final ListingDetailController controller = ListingDetailController(
      buildMarketplaceRepository(tokenStore, handler, recorded: recorded),
      12,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test('starts with nothing loaded', () {
    final ListingDetailController controller = build(
      (_) async => listingDetailResponse(),
    );

    expect(controller.state.status, ListingDetailStatus.initial);
    expect(controller.state.listing, isNull);
  });

  test('loads the listing from the detail endpoint', () async {
    final ListingDetailController controller = build(
      (_) async => listingDetailResponse(),
    );

    await controller.load();

    expect(recorded.single.method, 'GET');
    expect(recorded.single.apiPath, '/listings/12');
    expect(controller.state.status, ListingDetailStatus.ready);
    expect(controller.state.listing?.id, 12);
    expect(controller.state.listing?.seller.name, 'Rizal Farms');
  });

  test('publishes loading before the response arrives', () async {
    final Completer<http.Response> completer = Completer<http.Response>();
    final ListingDetailController controller = build((_) => completer.future);

    final List<ListingDetailStatus> seen = <ListingDetailStatus>[];
    controller.addListener(() => seen.add(controller.state.status));

    unawaited(controller.load());
    await pumpEventQueue();

    expect(seen, contains(ListingDetailStatus.loading));
    expect(controller.state.isLoading, isTrue);

    completer.complete(listingDetailResponse());
    await pumpEventQueue();
  });

  test('treats a 404 as unavailable, not as an error', () async {
    // A listing that went inactive, was sold, or belongs to another seller all
    // answer 404 by design, and the screen must not pretend to know which.
    final ListingDetailController controller = build(
      (_) async => listingNotFoundResponse(),
    );

    await controller.load();

    expect(controller.state.status, ListingDetailStatus.unavailable);
    expect(controller.state.isUnavailable, isTrue);
    expect(controller.state.listing, isNull);
    expect(
      controller.state.errorMessage,
      isNull,
      reason:
          'the server\'s 404 text is backend wording, not buyer-facing copy',
    );
  });

  test('surfaces other failures as a retryable error with a message', () async {
    final ListingDetailController controller = build(
      (_) async => throw http.ClientException('connection refused'),
    );

    await controller.load();

    expect(controller.state.status, ListingDetailStatus.failed);
    expect(controller.state.errorMessage, isNotNull);
  });

  test('a 403 is an error rather than an "unavailable" notice', () async {
    // A forbidden token is an auth problem the session must surface, not a
    // statement about the listing.
    final ListingDetailController controller = build(
      (_) async => forbiddenResponse(),
    );

    await controller.load();

    expect(controller.state.status, ListingDetailStatus.failed);
    expect(controller.state.isUnavailable, isFalse);
  });

  test('does not start a second request while one is in flight', () async {
    final Completer<http.Response> completer = Completer<http.Response>();
    final ListingDetailController controller = build((_) => completer.future);

    unawaited(controller.load());
    await pumpEventQueue();
    unawaited(controller.load());
    await pumpEventQueue();

    expect(recorded, hasLength(1));

    completer.complete(listingDetailResponse());
    await pumpEventQueue();
  });

  test('can be retried after a failure', () async {
    int calls = 0;
    final ListingDetailController controller = build((_) async {
      calls++;
      if (calls == 1) {
        throw http.ClientException('connection refused');
      }
      return listingDetailResponse();
    });

    await controller.load();
    expect(controller.state.status, ListingDetailStatus.failed);

    await controller.load();

    expect(controller.state.status, ListingDetailStatus.ready);
    expect(recorded, hasLength(2));
  });

  test(
    'a listing that became unavailable between list and detail renders as unavailable',
    () async {
      // The scenario the detail endpoint exists for: the buyer tapped a card, and
      // by the time the detail request landed the listing was gone. The screen
      // must not fall back to the list copy it was given.
      final ListingDetailController controller = build(
        (_) async => listingNotFoundResponse(),
      );

      await controller.load();

      expect(controller.state.status, ListingDetailStatus.unavailable);
      expect(controller.state.listing, isNull);
    },
  );

  test('does not publish after dispose', () async {
    final Completer<http.Response> completer = Completer<http.Response>();
    final ListingDetailController controller = ListingDetailController(
      buildMarketplaceRepository(
        tokenStore,
        (_) => completer.future,
        recorded: recorded,
      ),
      12,
    );

    unawaited(controller.load());
    await pumpEventQueue();

    controller.dispose();
    completer.complete(listingDetailResponse());
    await pumpEventQueue();

    expect(controller.state.status, ListingDetailStatus.loading);
  });
}
