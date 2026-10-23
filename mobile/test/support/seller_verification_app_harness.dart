import 'dart:typed_data';

import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/seller_verification/state/seller_verification_controller.dart';
import 'package:agrobenta_mobile/features/seller_verification/state/seller_verification_scope.dart';
import 'package:agrobenta_mobile/features/seller_verification/view/seller_verification_screen.dart';
import 'package:agrobenta_mobile/models/seller_verification.dart';
import 'package:agrobenta_mobile/repositories/seller_verification_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

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
      (RecordedRequest request) async => throw StateError(
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
      (RecordedRequest request) async => sellerVerificationNotFoundResponse(),
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
    String? accountName,
    Future<XFile?> Function(VerificationDocumentType type)? pickImage,
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
        repository: buildSellerVerificationRepository(
          tokenStore,
          handler,
          recorded: recorded,
        ),
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: SellerVerificationScreen(
            accountName: accountName,
            pickImage: pickImage,
          ),
        ),
      ),
    );
    await settleSellerVerification(tester);

    return SellerVerificationHarness._(
      controller,
      recorded,
      capabilityRefreshes,
    );
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
  final Finder target = find.widgetWithText(
    FilledButton,
    resubmission ? 'Resubmit Verification' : 'Get Started',
  );
  await tester.ensureVisible(target);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(target);
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
Future<void> settleSellerVerification(
  WidgetTester tester, {
  int frames = 12,
}) async {
  for (int frame = 0; frame < frames; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A tiny in-memory PNG an [XFile] can read, for picker injection in tests.
/// The bytes are a valid 1x1 PNG so `Image.file`/`Image.memory` would render if
/// ever asked to; the tests exercise the flow, not the pixels.
final Uint8List kFakeVerificationImageBytes = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

/// A picker that always returns a fresh in-memory PNG.
///
/// Distinct file names per type keep the two slots from looking identical, and
/// never reuse the same file across the ID and selfie cards — the design forbids
/// silently reusing the ID image as the selfie.
Future<XFile?> fakeVerificationPicker(VerificationDocumentType type) async {
  return XFile.fromData(
    kFakeVerificationImageBytes,
    name: '${type.value}.png',
    mimeType: 'image/png',
  );
}

/// A picker that returns `null` — the user cancelled the picker.
Future<XFile?> cancelledVerificationPicker(
  VerificationDocumentType type,
) async => null;

/// Taps the first pick action on a document card, identified by its card title.
Future<void> tapDocumentPick(
  WidgetTester tester,
  String cardTitle,
) async {
  final Finder card = find.ancestor(
    of: find.text(cardTitle),
    matching: find.byType(Card),
  );
  final Finder button = find.descendant(
    of: card,
    matching: find.widgetWithText(FilledButton, 'Take Photo'),
  );
  await tester.ensureVisible(button);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(button);
  await settleSellerVerification(tester);
}

/// Advances through the Documents step by uploading both required images.
Future<void> uploadBothDocuments(WidgetTester tester) async {
  await tapDocumentPick(tester, 'Valid Government-Issued ID');
  await tapDocumentPick(tester, 'Selfie Holding Your ID');
}
