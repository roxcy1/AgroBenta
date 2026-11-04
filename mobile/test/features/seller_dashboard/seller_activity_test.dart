import 'dart:async';

import 'package:agrobenta_mobile/features/seller_dashboard/state/seller_activities_controller.dart';
import 'package:agrobenta_mobile/features/seller_dashboard/state/seller_activity_controller.dart';
import 'package:agrobenta_mobile/models/seller_activity.dart';
import 'package:agrobenta_mobile/repositories/seller_activity_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/seller_dashboard_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  setUp(() {
    tokenStore = FakeTokenStore('token');
    recorded = <RecordedRequest>[];
  });

  SellerActivityRepository repository(
    Future<http.Response> Function(RecordedRequest request) handler,
  ) {
    return buildSellerActivityRepository(
      tokenStore,
      handler,
      recorded: recorded,
    );
  }

  group('model', () {
    test('parses the safe contract and typed context ids', () {
      final SellerActivity activity = SellerActivity.fromJson(sellerActivityJson());

      expect(activity.action, 'offer_accepted');
      expect(activity.label, 'Offer accepted');
      expect(activity.targetType, 'offer');
      expect(activity.targetId, 21);
      expect(activity.listingId, 4);
      expect(activity.buyerId, 7);
      expect(activity.transactionId, 31);
      expect(activity.inquiryId, isNull);
    });

    test('parses the real context-less response shape (empty JSON object)', () {
      final Map<String, dynamic> json = sellerActivityJson(
        action: 'listing_marked_sold',
        label: 'Listing marked as sold',
      );
      json['context'] = <String, dynamic>{};

      final SellerActivity activity = SellerActivity.fromJson(json);

      expect(activity.action, 'listing_marked_sold');
      expect(activity.listingId, isNull);
      expect(activity.buyerId, isNull);
      expect(activity.transactionId, isNull);
    });

    test('tolerates a legacy empty-array context instead of failing the feed', () {
      final Map<String, dynamic> json = sellerActivityJson();
      json['context'] = <dynamic>[];

      final SellerActivity activity = SellerActivity.fromJson(json);

      expect(activity.listingId, isNull);
      expect(activity.transactionId, isNull);
    });
  });

  group('request contract', () {
    test('calls the seller activities endpoint with the limit only', () async {
      await repository(
        (_) async => sellerActivityResponse(
          activities: <Map<String, dynamic>>[sellerActivityJson()],
        ),
      ).latest(limit: 5);

      expect(recorded.single.apiPath, '/seller/activities');
      expect(recorded.single.query, <String, String>{'limit': '5'});
      expect(recorded.single.method, 'GET');
    });

    test('page request sends pagination and filters together', () async {
      await repository(
        (_) async => sellerActivityResponse(
          activities: <Map<String, dynamic>>[sellerActivityJson()],
          currentPage: 2,
          lastPage: 4,
          perPage: 5,
          total: 16,
        ),
      ).page(
        page: 2,
        perPage: 5,
        category: 'offers',
        from: DateTime(2026, 11, 1),
        to: DateTime(2026, 11, 3),
      );

      expect(recorded.single.query, <String, String>{
        'page': '2',
        'per_page': '5',
        'category': 'offers',
        'from': '2026-11-01',
        'to': '2026-11-03',
      });
    });
  });

  group('controller', () {
    test('goes loading then ready and sends one request', () async {
      final Completer<http.Response> pending = Completer<http.Response>();
      final SellerActivityController controller = SellerActivityController(
        repository((_) => pending.future),
      );
      addTearDown(controller.dispose);

      final Future<void> load = controller.load();
      expect(controller.state.status, SellerActivityStatus.loading);

      pending.complete(
        sellerActivityResponse(
          activities: <Map<String, dynamic>>[sellerActivityJson()],
        ),
      );
      await load;

      expect(controller.state.status, SellerActivityStatus.ready);
      expect(controller.state.activities, hasLength(1));
      expect(recorded, hasLength(1));
    });

    test('an empty page becomes the empty state', () async {
      final SellerActivityController controller = SellerActivityController(
        repository((_) async => sellerActivityResponse()),
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.state.status, SellerActivityStatus.empty);
      expect(controller.state.activities, isEmpty);
    });

    test('a server failure becomes the error state and retry recovers', () async {
      final List<http.Response Function()> responses = <http.Response Function()>[
        () => sellerActivityResponse(statusCode: 500),
        sellerActivityResponse,
      ];
      final SellerActivityController controller = SellerActivityController(
        repository((_) async => responses.removeAt(0)()),
      );
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.state.hasFailed, isTrue);
      expect(controller.state.errorMessage, isNotEmpty);

      await controller.retry();
      expect(controller.state.status, SellerActivityStatus.empty);
      expect(recorded, hasLength(2));
    });

    test('refresh re-queries even after a successful load', () async {
      final SellerActivityController controller = SellerActivityController(
        repository((_) async => sellerActivityResponse()),
      );
      addTearDown(controller.dispose);

      await controller.load();
      expect(recorded, hasLength(1));

      await controller.refresh();
      expect(recorded, hasLength(2));
    });

    test('repeated load calls never duplicate the request', () async {
      final Completer<http.Response> pending = Completer<http.Response>();
      final SellerActivityController controller = SellerActivityController(
        repository((_) => pending.future),
      );
      addTearDown(controller.dispose);

      final Future<void> first = controller.load();
      await controller.load();
      await controller.load();
      await Future<void>.delayed(Duration.zero);
      expect(recorded, hasLength(1));

      pending.complete(sellerActivityResponse());
      await first;

      await controller.load();
      expect(recorded, hasLength(1), reason: 'ready/empty states are stable');
    });
  });

  group('all activities controller', () {
    SellerActivitiesController build(
      Future<http.Response> Function(RecordedRequest request) handler,
    ) {
      final SellerActivitiesController controller = SellerActivitiesController(
        repository(handler),
      );
      addTearDown(controller.dispose);
      return controller;
    }

    test('loads page one with pagination and appends page two', () async {
      final SellerActivitiesController controller = build((
        RecordedRequest request,
      ) async {
        final String page = request.query['page'] ?? '1';
        return sellerActivityResponse(
          activities: <Map<String, dynamic>>[
            sellerActivityJson(id: int.parse(page)),
          ],
          currentPage: int.parse(page),
          lastPage: 2,
          perPage: 1,
          total: 2,
        );
      });

      await controller.loadInitial();
      expect(controller.state.status, SellerActivitiesStatus.ready);
      expect(controller.state.hasMorePages, isTrue);

      await controller.loadMore();
      expect(controller.state.activities, hasLength(2));
      expect(controller.state.activities.last.id, 2);
      expect(controller.state.hasMorePages, isFalse);
    });

    test('category and date filters reset to page one with the query', () async {
      final SellerActivitiesController controller = build(
        (_) async => sellerActivityResponse(),
      );

      await controller.loadInitial();
      await controller.setCategory('offers');

      expect(recorded.last.query['category'], 'offers');
      expect(recorded.last.query['page'], '1');

      await controller.setDateRange(DateTime(2026, 11, 1), DateTime(2026, 11, 3));

      expect(recorded.last.query['from'], '2026-11-01');
      expect(recorded.last.query['to'], '2026-11-03');
      expect(recorded.last.query['category'], 'offers');

      await controller.clearFilters();
      expect(recorded.last.query.containsKey('category'), isFalse);
      expect(recorded.last.query.containsKey('from'), isFalse);
      expect(recorded.last.query.containsKey('to'), isFalse);
    });

    test('an empty filtered page becomes the empty state', () async {
      final SellerActivitiesController controller = build(
        (_) async => sellerActivityResponse(),
      );

      await controller.setCategory('transactions');

      expect(controller.state.status, SellerActivitiesStatus.empty);
      expect(controller.state.hasActiveFilters, isTrue);
    });

    test('an error is retryable and refresh keeps the active filter', () async {
      int calls = 0;
      final SellerActivitiesController controller = build((_) async {
        calls++;
        if (calls == 1) {
          return sellerActivityResponse(statusCode: 500);
        }
        return sellerActivityResponse(
          activities: <Map<String, dynamic>>[sellerActivityJson()],
        );
      });

      await controller.loadInitial();
      expect(controller.state.status, SellerActivitiesStatus.failed);

      await controller.retry();
      expect(controller.state.status, SellerActivitiesStatus.ready);

      await controller.setCategory('inquiries');
      await controller.refresh();

      expect(recorded.last.query['category'], 'inquiries');
    });

    test('repeated loadInitial calls do not duplicate the request', () async {
      final Completer<http.Response> pending = Completer<http.Response>();
      final SellerActivitiesController controller = build(
        (_) => pending.future,
      );

      final Future<void> first = controller.loadInitial();
      await controller.loadInitial();
      await controller.loadInitial();
      await Future<void>.delayed(Duration.zero);
      expect(recorded, hasLength(1));

      pending.complete(sellerActivityResponse());
      await first;
    });
  });
}
