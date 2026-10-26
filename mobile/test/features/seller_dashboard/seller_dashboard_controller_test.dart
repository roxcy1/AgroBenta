import 'package:agrobenta_mobile/features/seller_dashboard/state/seller_dashboard_controller.dart';
import 'package:agrobenta_mobile/features/seller_dashboard/state/seller_dashboard_state.dart';
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

  SellerDashboardController build(
    Future<http.Response> Function(RecordedRequest request) handler,
  ) {
    final SellerDashboardController controller = buildSellerDashboardController(
      tokenStore,
      handler,
      recorded: recorded,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test('starts initial with no dashboard', () {
    final SellerDashboardController controller = build(
      (_) async => sellerDashboardResponse(),
    );

    expect(controller.state.status, SellerDashboardStatus.initial);
    expect(controller.state.dashboard, isNull);
  });

  test('loads the dashboard and publishes the exact counts', () async {
    final SellerDashboardController controller = build(
      (_) async => sellerDashboardResponse(),
    );

    await controller.loadInitial();

    expect(controller.state.status, SellerDashboardStatus.ready);
    expect(controller.state.dashboard?.listings.total, 6);
    expect(controller.state.dashboard?.listings.active, 2);
    expect(controller.state.dashboard?.inquiries.total, 3);
    expect(controller.state.dashboard?.transactions.total, 4);
    expect(controller.state.dashboard?.transactions.pending, 2);
    expect(controller.state.isEmpty, isFalse);
    expect(recorded.single.apiPath, '/seller/dashboard');
  });

  test('an empty dashboard is ready and empty, not an error', () async {
    final SellerDashboardController controller = build(
      (_) async => sellerDashboardResponse(
        dashboard: sellerDashboardJson(
          totalListings: 0,
          draft: 0,
          pendingListings: 0,
          active: 0,
          sold: 0,
          inactive: 0,
          totalInquiries: 0,
          totalTransactions: 0,
          pendingTransactions: 0,
        ),
      ),
    );

    await controller.loadInitial();

    expect(controller.state.status, SellerDashboardStatus.ready);
    expect(controller.state.isEmpty, isTrue);
    expect(controller.state.errorMessage, isNull);
  });

  test('a first-load failure is displayable and retry recovers', () async {
    final List<http.Response Function()> responses = <http.Response Function()>[
      sellerDashboardServerErrorResponse,
      sellerDashboardResponse,
    ];
    final SellerDashboardController controller = build(
      (_) async => responses.removeAt(0)(),
    );

    await controller.loadInitial();

    expect(controller.state.status, SellerDashboardStatus.failed);
    expect(controller.state.errorMessage, 'Server error.');

    await controller.retry();

    expect(controller.state.status, SellerDashboardStatus.ready);
    expect(controller.state.dashboard?.listings.total, 6);
    expect(controller.state.errorMessage, isNull);
    expect(recorded, hasLength(2));
  });

  test(
    'a refresh failure keeps the last dashboard and shows a notice',
    () async {
      final List<http.Response Function()> responses =
          <http.Response Function()>[
            sellerDashboardResponse,
            sellerDashboardServerErrorResponse,
          ];
      final SellerDashboardController controller = build(
        (_) async => responses.removeAt(0)(),
      );

      await controller.loadInitial();
      await controller.refresh();

      expect(controller.state.status, SellerDashboardStatus.ready);
      expect(controller.state.dashboard?.listings.total, 6);
      expect(controller.state.refreshErrorMessage, 'Server error.');
      expect(controller.state.errorMessage, isNull);
    },
  );

  test('does not send a second load while one is in flight', () async {
    final SellerDashboardController controller = build(
      (_) async => sellerDashboardResponse(),
    );

    await Future.wait<void>(<Future<void>>[
      controller.loadInitial(),
      controller.loadInitial(),
    ]);

    expect(recorded, hasLength(1));
  });
}
