import 'dart:async';

import 'package:agrobenta_mobile/features/seller_verification/state/seller_verification_controller.dart';
import 'package:agrobenta_mobile/features/seller_verification/state/seller_verification_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/seller_verification_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  SellerVerificationController build(
    Future<http.Response> Function(RecordedRequest request) handler, {
    Future<bool> Function()? onCapabilityMayHaveChanged,
  }) {
    recorded = <RecordedRequest>[];
    return buildSellerVerificationController(
      tokenStore,
      handler,
      recorded: recorded,
      onCapabilityMayHaveChanged: onCapabilityMayHaveChanged,
    );
  }

  setUp(() => tokenStore = FakeTokenStore('1|mobile-token'));

  group('load()', () {
    test('reports "never submitted" for a 404, not a failure', () async {
      final SellerVerificationController controller = build(
        (_) async => sellerVerificationNotFoundResponse(),
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.state.status, SellerVerificationUiStatus.notSubmitted);
      expect(controller.state.verification, isNull);
      expect(controller.state.errorMessage, isNull);
      expect(controller.state.canSubmit, isTrue);
    });

    test('collapses submitted and pending_review into awaiting review', () async {
      for (final String status in <String>['submitted', 'pending_review']) {
        final SellerVerificationController controller = build(
          (_) async => sellerVerificationResponse(
            verification: sellerVerificationJson(status: status),
          ),
        );
        addTearDown(controller.dispose);

        await controller.load();

        // The buyer cannot act on the difference between the two, and both mean
        // "do not send another".
        expect(
          controller.state.status,
          SellerVerificationUiStatus.awaitingReview,
        );
        expect(controller.state.canSubmit, isFalse);
      }
    });

    test('reports a rejection and permits a resubmission', () async {
      final SellerVerificationController controller = build(
        (_) async => sellerVerificationResponse(
          verification: sellerVerificationJson(
            status: 'rejected',
            adminNote: 'Name does not match the reference.',
          ),
        ),
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.state.status, SellerVerificationUiStatus.rejected);
      expect(controller.state.canSubmit, isTrue);
      expect(controller.state.verification!.adminNote, isNotNull);
    });

    test('reports an approval and stops offering the form', () async {
      final SellerVerificationController controller = build(
        (_) async => sellerVerificationResponse(
          verification: sellerVerificationJson(status: 'approved'),
        ),
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.state.status, SellerVerificationUiStatus.approved);
      expect(controller.state.canSubmit, isFalse);
    });

    test('keeps the previous record visible when a reload fails', () async {
      var shouldFail = false;
      final SellerVerificationController controller = build((_) async {
        if (shouldFail) {
          throw http.ClientException('connection refused');
        }
        return sellerVerificationResponse();
      });
      addTearDown(controller.dispose);

      await controller.load();
      shouldFail = true;
      await controller.load();

      expect(controller.state.status, SellerVerificationUiStatus.failed);
      // The record is still on file; the screen is not. Blanking it would make a
      // transient network fault look like a lost application.
      expect(controller.state.verification, isNotNull);
      expect(controller.state.errorMessage, isNotNull);
    });

    test('ignores a second read while one is in flight', () async {
      var calls = 0;
      final SellerVerificationController controller = build((_) async {
        calls++;
        return sellerVerificationResponse();
      });
      addTearDown(controller.dispose);

      final Future<void> first = controller.load();
      final Future<void> second = controller.load();
      await Future.wait<void>(<Future<void>>[first, second]);

      expect(calls, 1, reason: 'one open, one read');
    });

    test('re-reads the account once after an approval', () async {
      final List<String> refreshes = <String>[];
      final SellerVerificationController controller = build(
        (_) async => sellerVerificationResponse(
          verification: sellerVerificationJson(status: 'approved'),
        ),
        onCapabilityMayHaveChanged: () async {
          refreshes.add('refreshed');
          return true;
        },
      );
      addTearDown(controller.dispose);

      await controller.load();
      await controller.load();

      // One refresh, not one per read: the account did not change twice.
      expect(refreshes, hasLength(1));
    });

    test('does not refresh the account for a non-approval', () async {
      final List<String> refreshes = <String>[];
      final SellerVerificationController controller = build(
        (_) async => sellerVerificationResponse(),
        onCapabilityMayHaveChanged: () async {
          refreshes.add('refreshed');
          return true;
        },
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(refreshes, isEmpty);
    });

    test('does not touch seller capability itself', () async {
      // Filing an application cannot make anybody a seller. The state carries a
      // verification and nothing else — there is no capability field to set, by
      // construction.
      final SellerVerificationController controller = build(
        (_) async => sellerVerificationCreatedResponse(),
      );
      addTearDown(controller.dispose);

      await controller.load();
      final bool created = await controller.submit(businessName: 'Rizal Farms');
      await Future<void>.delayed(Duration.zero);

      expect(created, isTrue);
      expect(
        controller.state.status,
        SellerVerificationUiStatus.awaitingReview,
      );
      expect(
        recorded.where((RecordedRequest r) => r.method == 'POST'),
        hasLength(1),
      );
    });
  });

  group('submit()', () {
    test('publishes the record the server created', () async {
      final SellerVerificationController controller = build(
        (_) async => sellerVerificationCreatedResponse(
          verification: sellerVerificationJson(id: 12, status: 'submitted'),
        ),
      );
      addTearDown(controller.dispose);
      await controller.load();

      final bool created = await controller.submit(businessName: 'Rizal Farms');

      expect(created, isTrue);
      expect(controller.state.verification!.id, 12);
      expect(
        controller.state.status,
        SellerVerificationUiStatus.awaitingReview,
      );
    });

    test('a second tap while submitting does not reach the network', () async {
      final Completer<http.Response> gate = Completer<http.Response>();
      var posts = 0;
      final SellerVerificationController controller = build((
        RecordedRequest request,
      ) async {
        if (request.method == 'POST') {
          posts++;
          return gate.future;
        }
        return sellerVerificationResponse();
      });
      addTearDown(controller.dispose);
      await controller.load();

      final Future<bool> first = controller.submit(businessName: 'Rizal Farms');
      final bool second = await controller.submit(businessName: 'Rizal Farms');

      expect(second, isFalse);

      gate.complete(sellerVerificationCreatedResponse());
      expect(await first, isTrue);

      // Counted after the first submission resolves, because the request only
      // reaches the transport once the token has been read from secure storage.
      // The assertion is about the total, not about when it happens.
      expect(posts, 1, reason: 'the duplicate tap must not be sent');
    });

    test('surfaces 422 field errors without losing the form', () async {
      // A first application: nothing on file, so a `422` is the ordinary
      // "something in that form is wrong" case and the screen must stay on the
      // form the user was filling in.
      final SellerVerificationController controller = build(
        (RecordedRequest request) async => request.method == 'POST'
            ? sellerVerificationValidationResponse(
                errors: <String, Object>{
                  'business_name': <String>[
                    'The business name field is required.',
                  ],
                },
              )
            : sellerVerificationNotFoundResponse(),
      );
      addTearDown(controller.dispose);
      await controller.load();

      final bool created = await controller.submit(businessName: '');

      expect(created, isFalse);
      expect(
        controller.state.errorFor('business_name'),
        'The business name field is required.',
      );
      // Back to the state the form was opened from, so the user keeps their
      // place instead of staring at a spinner.
      expect(controller.state.status, SellerVerificationUiStatus.notSubmitted);
    });

    test(
      'a 422 after a rejection stays on the rejection, not the form',
      () async {
        // The other half of the same rule: a resubmission that fails must return to
        // the rejected state, so the reason stays on screen next to the retry.
        final SellerVerificationController controller = build(
          (RecordedRequest request) async => request.method == 'POST'
              ? sellerVerificationValidationResponse()
              : sellerVerificationResponse(
                  verification: sellerVerificationJson(
                    status: 'rejected',
                    adminNote: 'Name does not match the reference.',
                  ),
                ),
        );
        addTearDown(controller.dispose);
        await controller.load();

        await controller.submit(businessName: '');

        expect(controller.state.status, SellerVerificationUiStatus.rejected);
        expect(controller.state.verification!.adminNote, isNotNull);
      },
    );

    test('treats a 409 as information and re-reads the real state', () async {
      var reads = 0;
      final SellerVerificationController controller = build((
        RecordedRequest request,
      ) async {
        if (request.method == 'POST') {
          return sellerVerificationConflictResponse();
        }
        reads++;
        // The server says one is already open; the follow-up read proves it.
        return sellerVerificationResponse(
          verification: sellerVerificationJson(id: 3, status: 'pending_review'),
        );
      });
      addTearDown(controller.dispose);
      await controller.load();

      final bool created = await controller.submit(businessName: 'Rizal Farms');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(created, isFalse);
      expect(reads, 2, reason: 'one read, then one to settle after the 409');
      expect(controller.state.conflictMessage, isNotNull);
      expect(
        controller.state.status,
        SellerVerificationUiStatus.awaitingReview,
      );
    });

    test('reports a 403 as a form-level error, not a field error', () async {
      final SellerVerificationController controller = build(
        (RecordedRequest request) async => request.method == 'POST'
            ? sellerVerificationForbiddenResponse()
            : sellerVerificationResponse(),
      );
      addTearDown(controller.dispose);
      await controller.load();

      await controller.submit(businessName: 'Rizal Farms');

      expect(controller.state.errorMessage, contains('approved seller'));
      expect(controller.state.validationErrors, isEmpty);
    });

    test('clearError() drops the form-level and conflict messages', () async {
      final SellerVerificationController controller = build((
        RecordedRequest request,
      ) async {
        if (request.method == 'POST') {
          return sellerVerificationConflictResponse();
        }
        return sellerVerificationResponse();
      });
      addTearDown(controller.dispose);
      await controller.load();
      await controller.submit(businessName: 'Rizal Farms');

      controller.clearError();

      expect(controller.state.errorMessage, isNull);
      expect(controller.state.conflictMessage, isNull);
    });
  });
}
