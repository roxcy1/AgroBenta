import 'dart:async';

import 'package:agrobenta_mobile/features/seller_verification/view/seller_verification_form_screen.dart';
import 'package:agrobenta_mobile/features/seller_verification/view/seller_verification_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/seller_verification_app_harness.dart';
import '../../support/seller_verification_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;

  setUp(() => tokenStore = FakeTokenStore('1|mobile-token'));

  group('status screen', () {
    testWidgets('offers to apply when nothing has been submitted', (
      WidgetTester tester,
    ) async {
      await SellerVerificationHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => sellerVerificationNotFoundResponse(),
      );

      expect(find.text('Become a Seller'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Start seller verification'),
        findsOneWidget,
      );
    });

    testWidgets('shows an open application as under review, with no form', (
      WidgetTester tester,
    ) async {
      await SellerVerificationHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => sellerVerificationResponse(
          verification: sellerVerificationJson(status: 'pending_review'),
        ),
      );

      expect(find.text('Under review'), findsOneWidget);
      // No way to start another application: the server answers that with a 409,
      // so offering the form here would walk the user into a dead end.
      expect(
        find.widgetWithText(FilledButton, 'Start seller verification'),
        findsNothing,
      );
      expect(
        find.widgetWithText(FilledButton, 'Resubmit Verification'),
        findsNothing,
      );
    });

    testWidgets('shows the reason for a rejection and offers a resubmission', (
      WidgetTester tester,
    ) async {
      await SellerVerificationHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => sellerVerificationResponse(
          verification: sellerVerificationJson(
            status: 'rejected',
            adminNote: 'Business name does not match the reference.',
          ),
        ),
      );

      expect(find.text('Not approved'), findsOneWidget);
      expect(
        find.text('Business name does not match the reference.'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'Resubmit Verification'),
        findsOneWidget,
      );
    });

    testWidgets('never invents a reason when the administrator gave none', (
      WidgetTester tester,
    ) async {
      await SellerVerificationHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => sellerVerificationResponse(
          verification: sellerVerificationJson(
            status: 'rejected',
            adminNote: null,
          ),
        ),
      );

      expect(find.text('Not approved'), findsOneWidget);
      expect(find.text('Reason given'), findsNothing);
    });

    testWidgets('reports an approval without offering the form', (
      WidgetTester tester,
    ) async {
      await SellerVerificationHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => sellerVerificationResponse(
          verification: sellerVerificationJson(status: 'approved'),
        ),
      );

      expect(find.text('Approved — you are a seller'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Start seller verification'),
        findsNothing,
      );
      expect(
        find.widgetWithText(FilledButton, 'Resubmit Verification'),
        findsNothing,
      );
    });

    testWidgets('re-reads the account when an approval is shown', (
      WidgetTester tester,
    ) async {
      final SellerVerificationHarness harness =
          await SellerVerificationHarness.pump(
            tester,
            tokenStore: tokenStore,
            handler: (_) async => sellerVerificationResponse(
              verification: sellerVerificationJson(status: 'approved'),
            ),
          );

      // The capability lives on the account, so the app asks `/auth/me` again
      // rather than deciding from the application record.
      expect(harness.capabilityRefreshes, hasLength(1));
    });

    testWidgets('offers a retry when the read fails', (
      WidgetTester tester,
    ) async {
      await SellerVerificationHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => throw http.ClientException('connection refused'),
      );

      expect(
        find.text('Could not load your seller verification'),
        findsOneWidget,
      );
      expect(find.widgetWithText(OutlinedButton, 'Try again'), findsOneWidget);
    });
  });

  group('form', () {
    testWidgets('asks for exactly the four contract fields', (
      WidgetTester tester,
    ) async {
      await SellerVerificationHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => sellerVerificationNotFoundResponse(),
      );
      await openSellerVerificationForm(tester, resubmission: false);

      expect(find.byType(SellerVerificationFormScreen), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(4));
      expect(find.text('Business name'), findsOneWidget);
      expect(find.text('Business location'), findsOneWidget);
      expect(find.text('Business description'), findsOneWidget);
      expect(find.text('ID document reference'), findsOneWidget);
    });

    testWidgets('offers no upload for the document reference', (
      WidgetTester tester,
    ) async {
      await SellerVerificationHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => sellerVerificationNotFoundResponse(),
      );
      await openSellerVerificationForm(tester, resubmission: false);

      // There is no upload endpoint, so anything collecting a file would be
      // collecting data with nowhere to go. The field is a plain text input that
      // says so.
      expect(
        find.textContaining('do not send the document'),
        findsOneWidget,
        reason: 'the field must say it is a reference, not an upload',
      );
      expect(find.textContaining('Attach'), findsNothing);
      expect(find.textContaining('Upload'), findsNothing);
      expect(
        find.widgetWithText(TextFormField, 'ID document reference'),
        findsOneWidget,
      );
    });

    testWidgets('requires a business name before sending anything', (
      WidgetTester tester,
    ) async {
      final SellerVerificationHarness harness =
          await SellerVerificationHarness.pump(
            tester,
            tokenStore: tokenStore,
            handler: (_) async => sellerVerificationNotFoundResponse(),
          );
      await openSellerVerificationForm(tester, resubmission: false);

      await tester.tap(find.widgetWithText(FilledButton, 'Submit application'));
      await settleSellerVerification(tester);

      expect(find.text('Enter your business name.'), findsOneWidget);
      expect(
        harness.recorded.where((RecordedRequest r) => r.method == 'POST'),
        isEmpty,
        reason: 'a locally invalid form must not be sent',
      );
    });

    testWidgets('submits and returns to the under-review status', (
      WidgetTester tester,
    ) async {
      final SellerVerificationHarness harness =
          await SellerVerificationHarness.pump(
            tester,
            tokenStore: tokenStore,
            handler: (RecordedRequest request) async => request.method == 'POST'
                ? sellerVerificationCreatedResponse()
                : sellerVerificationNotFoundResponse(),
          );
      await openSellerVerificationForm(tester, resubmission: false);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Business name'),
        'Rizal Farms',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Submit application'));
      await settleSellerVerification(tester);

      // Back on the status screen, showing what the server recorded — not an
      // invented "you are a seller".
      expect(find.byType(SellerVerificationFormScreen), findsNothing);
      expect(find.byType(SellerVerificationScreen), findsOneWidget);
      expect(find.text('Under review'), findsOneWidget);
      expect(
        harness.recorded
            .singleWhere((RecordedRequest r) => r.method == 'POST')
            .body,
        containsPair('business_name', 'Rizal Farms'),
      );
    });

    testWidgets('shows a 422 on the field it belongs to', (
      WidgetTester tester,
    ) async {
      await SellerVerificationHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (RecordedRequest request) async => request.method == 'POST'
            ? sellerVerificationValidationResponse(
                errors: <String, Object>{
                  'business_name': <String>[
                    'The business name field is required.',
                  ],
                },
              )
            : sellerVerificationNotFoundResponse(),
      );
      await openSellerVerificationForm(tester, resubmission: false);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Business name'),
        'Rizal Farms',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Submit application'));
      await settleSellerVerification(tester);

      // Inline on the field, and the form is still there with the typed value.
      expect(find.text('The business name field is required.'), findsOneWidget);
      expect(find.byType(SellerVerificationFormScreen), findsOneWidget);
    });

    testWidgets('reports a 409 as information, not as an error', (
      WidgetTester tester,
    ) async {
      // Realistic shape: nothing on file when the form is opened, and the
      // server turns out to already have an application — a second device, or an
      // administrator opening a review. The follow-up read is what proves it.
      var reads = 0;
      await SellerVerificationHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (RecordedRequest request) async {
          if (request.method == 'POST') {
            return sellerVerificationConflictResponse();
          }
          reads++;
          return reads == 1
              ? sellerVerificationNotFoundResponse()
              : sellerVerificationResponse(
                  verification: sellerVerificationJson(
                    status: 'pending_review',
                  ),
                );
        },
      );
      await openSellerVerificationForm(tester, resubmission: false);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Business name'),
        'Rizal Farms',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Submit application'));
      await settleSellerVerification(tester);

      // Amber information, not a red failure: the user did nothing wrong and
      // there is nothing for them to fix.
      expect(
        find.text('A seller verification is already open for review.'),
        findsOneWidget,
      );
      expect(find.byType(SellerVerificationFormScreen), findsOneWidget);
    });

    testWidgets('disables the submit button while a submission is in flight', (
      WidgetTester tester,
    ) async {
      // The POST is held open on purpose: with a handler that answered
      // immediately the state would cycle through `submitting` and back inside a
      // single frame, and the assertion would pass for the wrong reason.
      final Completer<http.Response> gate = Completer<http.Response>();
      await SellerVerificationHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (RecordedRequest request) async => request.method == 'POST'
            ? gate.future
            : sellerVerificationNotFoundResponse(),
      );
      await openSellerVerificationForm(tester, resubmission: false);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Business name'),
        'Rizal Farms',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Submit application'));
      // One frame: enough to start the request, nowhere near enough to finish it.
      await tester.pump(const Duration(milliseconds: 10));

      // The button stops the tap; the controller's guard stops a second request
      // when one is already on its way. Both have to be true to make the
      // duplicate-submission rule hold.
      //
      // Found by type, not by label: while submitting the button shows a spinner
      // instead of its text, which is the visible half of "it is disabled".
      final FilledButton button = tester.widget<FilledButton>(
        find.byType(FilledButton),
      );
      expect(button.onPressed, isNull);
      expect(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      gate.complete(sellerVerificationCreatedResponse());
      await settleSellerVerification(tester, frames: 20);
    });

    testWidgets('prefills a resubmission with the rejected values', (
      WidgetTester tester,
    ) async {
      await SellerVerificationHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => sellerVerificationResponse(
          verification: sellerVerificationJson(
            status: 'rejected',
            businessName: 'Santos Cattle Co.',
            businessLocation: 'Mabalacat, Pampanga',
            adminNote: 'Name does not match the reference.',
          ),
        ),
      );
      await openSellerVerificationForm(tester, resubmission: true);

      // Correcting a rejected application should not start from a blank form.
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Business name'),
            )
            .controller!
            .text,
        'Santos Cattle Co.',
      );
      expect(find.text('Resubmit verification'), findsWidgets);
    });
  });
}
