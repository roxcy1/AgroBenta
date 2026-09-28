import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/seller_verification/state/seller_verification_controller.dart';
import 'package:agrobenta_mobile/features/seller_verification/state/seller_verification_scope.dart';
import 'package:agrobenta_mobile/features/seller_verification/view/seller_verification_screen.dart';
import 'package:agrobenta_mobile/repositories/seller_verification_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'auth_fakes.dart';
import 'seller_verification_fakes.dart';

/// A repository that fails loudly if anything reaches for it.
///
/// [SellerVerificationScope] requires one because the production scope carries
/// both, and a harness that skipped it would not reproduce the real tree. Tests
/// supply their own controller, so nothing should ever call through this — and
/// if something does, a loud failure beats a silent second transport.
SellerVerificationRepository unusedRepository() =>
    buildSellerVerificationRepository(
      FakeTokenStore('unused'),
      (RecordedRequest request) async =>
          throw StateError(
            'The test did not expect a seller verification request to '
            '${request.method} ${request.apiPath}.',
          ),
    );

/// Wraps [child] in a [SellerVerificationScope], as `main.dart` does.
///
/// Exists so a test that only needs some *other* screen — the auth tests, the
/// buyer shell — can still mount a tree with the scopes the real app has. The
/// Home screen's seller card reads this scope, so a harness that omits it would
/// assert for a reason that has nothing to do with what it is testing.
class SellerVerificationTestScope extends StatelessWidget {
  const SellerVerificationTestScope({
    required this.controller,
    required this.child,
    super.key,
  });

  final SellerVerificationController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SellerVerificationScope(
      repository: unusedRepository(),
      controller: controller,
      child: child,
    );
  }
}

/// A [SellerVerificationScope] whose read answers "never submitted".
///
/// For tests whose subject is some *other* screen — the auth flows, the buyer
/// shell — and which would otherwise need a transport just to satisfy the Home
/// screen's seller card. The card renders its normal "Become a Seller" state and
/// nothing goes over the wire.
///
/// Owns the controller, so a test cannot leak one.
class NeverSubmittedVerificationScope extends StatefulWidget {
  const NeverSubmittedVerificationScope({required this.child, super.key});

  final Widget child;

  @override
  State<NeverSubmittedVerificationScope> createState() =>
      _NeverSubmittedVerificationScopeState();
}

class _NeverSubmittedVerificationScopeState
    extends State<NeverSubmittedVerificationScope> {
  late final SellerVerificationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = buildSellerVerificationController(
      FakeTokenStore('unused'),
      (RecordedRequest request) async =>
          sellerVerificationNotFoundResponse(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SellerVerificationScope(
      repository: unusedRepository(),
      controller: _controller,
      child: widget.child,
    );
  }
}

/// Pumps a seller verification screen over a mock transport.
class SellerVerificationHarness {
  SellerVerificationHarness._(
    this.controller,
    this.recorded,
    this.capabilityRefreshes,
  );

  final SellerVerificationController controller;
  final List<RecordedRequest> recorded;

  /// Appended to when the controller asks for `/auth/me` to be re-read after an
  /// approval, so a test can assert the capability refresh happened — and that it
  /// happened exactly once.
  ///
  /// The **live** list the controller closes over, not a copy, so a refresh
  /// triggered part-way through a test is still recorded.
  final List<String> capabilityRefreshes;

  static Future<SellerVerificationHarness> pump(
    WidgetTester tester, {
    required FakeTokenStore tokenStore,
    required Future<http.Response> Function(RecordedRequest request) handler,
  }) async {
    final List<RecordedRequest> recorded = <RecordedRequest>[];
    final List<String> capabilityRefreshes = <String>[];

    final SellerVerificationController controller =
        buildSellerVerificationController(
          tokenStore,
          handler,
          recorded: recorded,
          onCapabilityMayHaveChanged: () async {
            capabilityRefreshes.add('refreshed');
            return true;
          },
        );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      // Above `MaterialApp`, exactly as `main.dart` does it. The form is a
      // pushed route, and a scope inside `home` would be invisible to it.
      SellerVerificationScope(
        repository: unusedRepository(),
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SellerVerificationScreen(),
        ),
      ),
    );
    await settleSellerVerification(tester);

    return SellerVerificationHarness._(controller, recorded, capabilityRefreshes);
  }
}

/// Taps through from the status screen to the form, as a user does.
///
/// The form is pushed rather than mounted as `home`, so `Navigator.pop` after a
/// successful submission pops back to a real status screen — the behaviour worth
/// testing is that the user lands on "under review", and a lone form as the only
/// route would let that pop succeed vacuously.
Future<void> openSellerVerificationForm(
  WidgetTester tester, {
  required bool resubmission,
}) async {
  await tester.tap(
    find.widgetWithText(
      FilledButton,
      resubmission ? 'Resubmit Verification' : 'Start seller verification',
    ),
  );
  await settleSellerVerification(tester);
}

/// Pumps a bounded number of frames.
///
/// `pumpAndSettle` cannot be used: a `CircularProgressIndicator` schedules
/// frames forever, so the tree never "settles" while a spinner is on screen.
/// A fixed number of pumps is enough to let the mock transport answer and the
/// resulting state change rebuild the tree.
///
/// The default of 12 covers a route transition as well as the request: popping
/// the form after a successful submission takes ~300ms, so too few frames leaves
/// the form mid-transition and still in the tree, and an assertion about where
/// the user ended up would then be reading a frame that never existed.
Future<void> settleSellerVerification(WidgetTester tester, {int frames = 12}) async {
  for (int frame = 0; frame < frames; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
