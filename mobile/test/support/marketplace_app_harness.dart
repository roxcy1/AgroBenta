import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/marketplace/state/marketplace_controller.dart';
import 'package:agrobenta_mobile/features/marketplace/state/marketplace_scope.dart';
import 'package:agrobenta_mobile/features/marketplace/views/marketplace_screen.dart';
import 'package:agrobenta_mobile/repositories/marketplace_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'auth_fakes.dart';
import 'marketplace_fakes.dart';

/// Pumps the marketplace screen over a mock transport, with the same
/// `MarketplaceScope` shape `main.dart` installs.
///
/// The screen is pumped on its own rather than inside the buyer shell so a
/// listing-card tap has somewhere to push to without the shell's navigation
/// getting in the way. The shell has its own test.
class MarketplaceHarness {
  const MarketplaceHarness._(this.controller, this.recorded, this.repository);

  final MarketplaceController controller;
  final List<RecordedRequest> recorded;
  final MarketplaceRepository repository;

  /// Screens the harness has mounted, so a test can assert on a pushed route.
  static Future<MarketplaceHarness> pump(
    WidgetTester tester, {
    required FakeTokenStore tokenStore,
    required Future<http.Response> Function(RecordedRequest request) handler,
  }) async {
    final List<RecordedRequest> recorded = <RecordedRequest>[];
    final MarketplaceRepository repository = buildMarketplaceRepository(
      tokenStore,
      handler,
      recorded: recorded,
    );
    final MarketplaceController controller = MarketplaceController(repository);
    addTearDown(controller.dispose);

    // The default test surface is 800x600 logical, which is only a couple of
    // image-on-top results cards tall — too short for the load-more footer or a
    // second card to be built by the lazy list, hiding them from finders. A
    // taller portrait surface makes the assertions about a page of results mean
    // something.
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      // The scope sits **above** `MaterialApp`, exactly as `main.dart` does it.
      // A pushed route is a sibling of the home route inside the navigator's
      // overlay, so a scope inside `home` would not be visible to the detail
      // screen and the harness would not reproduce the real tree.
      MarketplaceScope(
        repository: repository,
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const MarketplaceScreen(),
        ),
      ),
    );
    await settleMarketplace(tester);

    return MarketplaceHarness._(controller, recorded, repository);
  }
}

/// Pumps a bounded number of frames.
///
/// `pumpAndSettle` cannot be used: a `CircularProgressIndicator` schedules
/// frames forever, so the tree never "settles" while a spinner is on screen.
/// The same rule applies here as in the auth harness.
Future<void> settleMarketplace(WidgetTester tester, {int frames = 8}) async {
  for (int frame = 0; frame < frames; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
