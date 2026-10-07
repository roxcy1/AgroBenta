import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/seller_listings/state/seller_listing_controller.dart';
import 'package:agrobenta_mobile/features/seller_listings/state/seller_listing_scope.dart';
import 'package:agrobenta_mobile/features/seller_listings/view/seller_listings_screen.dart';
import 'package:agrobenta_mobile/repositories/seller_listing_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'seller_listing_fakes.dart';

/// Pumps My Listings over a mock transport, with the same `SellerListingScope`
/// shape `main.dart` installs.
///
/// The scope sits above `MaterialApp` here for the same reason it does in the
/// app: the detail, form and delete-confirmation screens are pushed routes, and
/// a scope inside `home` would not be visible to any of them. A harness that got
/// this wrong would pass a test the real tree would fail.
class SellerListingsHarness {
  const SellerListingsHarness._(
    this.controller,
    this.recorded,
    this.repository,
  );

  final SellerListingController controller;
  final List<RecordedRequest> recorded;
  final SellerListingRepository repository;

  /// Mounts the screen and settles the initial page load.
  static Future<SellerListingsHarness> pump(
    WidgetTester tester, {
    required Future<http.Response> Function(RecordedRequest request) handler,
    String? token = '1|test-mobile-token',
  }) async {
    final List<RecordedRequest> recorded = <RecordedRequest>[];
    final SellerListingRepository repository = buildSellerListingRepository(
      FakeTokenStore(token),
      handler,
      recorded: recorded,
    );
    final SellerListingController controller = SellerListingController(
      repository,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      SellerListingScope(
        repository: repository,
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SellerListingsScreen(),
        ),
      ),
    );
    await settleSellerListings(tester);

    return SellerListingsHarness._(controller, recorded, repository);
  }

  /// Mounts the screen **without** letting the initial load settle, so a test can
  /// observe the loading state or drive the controller before the first page
  /// arrives.
  static Future<SellerListingsHarness> pumpPending(
    WidgetTester tester, {
    required Future<http.Response> Function(RecordedRequest request) handler,
  }) async {
    final List<RecordedRequest> recorded = <RecordedRequest>[];
    final SellerListingRepository repository = buildSellerListingRepository(
      FakeTokenStore('1|test-mobile-token'),
      handler,
      recorded: recorded,
    );
    final SellerListingController controller = SellerListingController(
      repository,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      SellerListingScope(
        repository: repository,
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SellerListingsScreen(),
        ),
      ),
    );
    // Two frames, not eight: enough for `initState` and the first `build`, and
    // not enough for a request that is deliberately left hanging.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    return SellerListingsHarness._(controller, recorded, repository);
  }
}

/// Pumps a bounded number of frames.
///
/// `pumpAndSettle` cannot be used here: a `CircularProgressIndicator` schedules
/// frames forever, so the tree never settles while a spinner is on screen.
Future<void> settleSellerListings(WidgetTester tester, {int frames = 8}) async {
  for (int frame = 0; frame < frames; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
