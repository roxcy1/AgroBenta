import 'dart:async';

import 'package:agrobenta_mobile/features/seller_verification/view/seller_verification_form_screen.dart';
import 'package:agrobenta_mobile/features/seller_verification/view/seller_verification_screen.dart';
import 'package:agrobenta_mobile/features/seller_verification/view/seller_verification_submitted_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/seller_verification_app_harness.dart';
import '../../support/seller_verification_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;

  setUp(() => tokenStore = FakeTokenStore('1|mobile-token'));

  /// Taps a filled button, scrolling it into view first.
  ///
  /// The default 800x600 test fold is shorter than the form, so a button below
  /// the last field would be tapped at an offset outside the render tree and the
  /// tap would silently miss.
  Future<void> tapFilled(WidgetTester tester, String label) async {
    final Finder target = find.widgetWithText(FilledButton, label);
    await tester.ensureVisible(target);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(target);
    await settleSellerVerification(tester);
  }

  /// Advances the wizard from Basic Information to Review.
  Future<void> tapNext(WidgetTester tester) => tapFilled(tester, 'Next');

  group('status screen', () {
    testWidgets('introduces the flow when nothing has been submitted', (
      WidgetTester tester,
    ) async {
      await SellerVerificationHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => sellerVerificationNotFoundResponse(),
      );

      expect(find.text('Become a Seller'), findsOneWidget);
      expect(find.text('Start Selling on AgroBenta'), findsOneWidget);
      // The four benefit rows from the reference.
      expect(find.text('List your livestock'), findsOneWidget);
      expect(find.text('Get verified'), findsOneWidget);
      expect(find.text('Manage your listings'), findsOneWidget);
      expect(find.text('Connect with buyers'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Get Started'),
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
      // The submission date comes from the API record, and the app bar is the
      // details title once a record exists.
      expect(find.text('Seller Application'), findsOneWidget);
      expect(find.text('Submitted'), findsOneWidget);
      // No way to start another application: the server answers that with a 409,
      // so offering the form here would walk the user into a dead end.
      expect(
        find.widgetWithText(FilledButton, 'Get Started'),
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

    testWidgets('never invents a reason for a rejection', (
      WidgetTester tester,
    ) async {
      await SellerVerificationHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => sellerVerificationResponse(
          verification: sellerVerificationJson(status: 'rejected'),
        ),
      );

      expect(find.text('Not approved'), findsOneWidget);
      expect(find.text('Reason given'), findsNothing);
    });

    testWidgets('shows the approved state and offers no form', (
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
      expect(find.widgetWithText(FilledButton, 'Get Started'), findsNothing);
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
    testWidgets('asks only for the supported fields, never lead with unsupported ones', (
      WidgetTester tester,
    ) async {
      await SellerVerificationHarness.pump(
        tester,
        tokenStore: tokenStore,
        accountName: 'Ana Reyes',
        handler: (_) async => sellerVerificationNotFoundResponse(),
      );
      await openSellerVerificationForm(tester, resubmission: false);

      expect(find.byType(SellerVerificationFormScreen), findsOneWidget);

      // Full name is read-only account data, plus the three writable contract
      // fields. The reference's Phone Number is not sent and not shown, and the
      // ID document reference is gone with the Documents step.
      expect(find.byType(TextFormField), findsNWidgets(4));
      expect(find.text('Full name'), findsOneWidget);
      expect(find.text('Business name'), findsOneWidget);
      expect(find.text('Business location'), findsOneWidget);
      expect(find.text('Business description'), findsOneWidget);
      expect(find.text('Phone Number'), findsNothing);
      expect(find.text('ID document reference'), findsNothing);
    });

    testWidgets('collects both required documents on the Documents step', (
      WidgetTester tester,
    ) async {
      await SellerVerificationHarness.pump(
        tester,
        tokenStore: tokenStore,
        pickImage: fakeVerificationPicker,
        handler: (_) async => sellerVerificationNotFoundResponse(),
      );
      await openSellerVerificationForm(tester, resubmission: false);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Business name'),
        'Rizal Farms',
      );
      await tapNext(tester);

      // The Documents step is the only place the flow offers an upload, and it
      // asks for the two pieces of evidence the design requires separately.
      expect(find.text('Valid Government-Issued ID'), findsOneWidget);
      expect(find.text('Selfie Holding Your ID'), findsOneWidget);
      expect(find.textContaining('Take Photo'), findsWidgets);
      // The ID image is never offered as the selfie — they are distinct.
      expect(find.textContaining('cannot be reused'), findsOneWidget);
    });

    testWidgets('requires a business name before advancing', (
      WidgetTester tester,
    ) async {
      final SellerVerificationHarness harness =
          await SellerVerificationHarness.pump(
            tester,
            tokenStore: tokenStore,
            handler: (_) async => sellerVerificationNotFoundResponse(),
          );
      await openSellerVerificationForm(tester, resubmission: false);

      await tapNext(tester);

      expect(find.text('Enter your business name.'), findsOneWidget);
      // Still on Basic Information, and nothing was sent.
      expect(find.text('Upload Required Documents'), findsNothing);
      expect(find.text('Review Your Information'), findsNothing);
      expect(
        harness.recorded.where((RecordedRequest r) => r.method == 'POST'),
        isEmpty,
        reason: 'a locally invalid form must not be sent',
      );
    });

    testWidgets('reveals the review step and can go back', (
      WidgetTester tester,
    ) async {
      await SellerVerificationHarness.pump(
        tester,
        tokenStore: tokenStore,
        pickImage: fakeVerificationPicker,
        handler: (RecordedRequest request) async =>
            request.apiPath == '/seller-verification/documents'
            ? sellerVerificationDocumentUploadedResponse()
            : sellerVerificationNotFoundResponse(),
      );
      await openSellerVerificationForm(tester, resubmission: false);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Business name'),
        'Rizal Farms',
      );
      await tapNext(tester);
      await uploadBothDocuments(tester);
      await tapNext(tester);

      expect(find.text('Review Your Information'), findsOneWidget);
      expect(find.text('Rizal Farms'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Submit Application'),
        findsOneWidget,
      );

      final Finder back = find.widgetWithText(OutlinedButton, 'Back');
      await tester.ensureVisible(back);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(back);
      await settleSellerVerification(tester);

      // Back returns to the Documents step, whose two uploads are intact.
      expect(find.text('Upload Required Documents'), findsOneWidget);
      expect(find.text('Review Your Information'), findsNothing);
    });

    testWidgets('submits only the supported fields and confirms on the server', (
      WidgetTester tester,
    ) async {
      final SellerVerificationHarness harness =
          await SellerVerificationHarness.pump(
            tester,
            tokenStore: tokenStore,
            pickImage: fakeVerificationPicker,
            handler: (RecordedRequest request) async {
              if (request.method == 'POST' &&
                  request.apiPath == '/seller-verification/documents') {
                return sellerVerificationDocumentUploadedResponse();
              }
              if (request.method == 'POST') {
                return sellerVerificationCreatedResponse();
              }
              return sellerVerificationNotFoundResponse();
            },
          );
      await openSellerVerificationForm(tester, resubmission: false);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Business name'),
        'Rizal Farms',
      );
      await tapNext(tester);
      await uploadBothDocuments(tester);
      await tapNext(tester);
      await tapFilled(tester, 'Submit Application');

      // The success screen appears only after the backend answers, and the body
      // is an explicit allow-list — no `status`, `role`, `seller_capability` or
      // `id_document_ref` can leak out.
      expect(find.byType(SellerVerificationFormScreen), findsNothing);
      expect(find.byType(SellerVerificationSubmittedScreen), findsOneWidget);
      expect(find.text('Application Submitted!'), findsOneWidget);

      final Map<String, dynamic> body = harness.recorded
          .singleWhere(
            (RecordedRequest r) =>
                r.method == 'POST' &&
                r.apiPath == '/seller-verification',
          )
          .body;
      expect(body, containsPair('business_name', 'Rizal Farms'));
      expect(body.containsKey('seller_capability'), isFalse);
      expect(body.containsKey('role'), isFalse);
      expect(body.containsKey('status'), isFalse);
      expect(body.containsKey('id_document_ref'), isFalse);

      // "Back to Profile" returns to where the flow was entered.
      await tapFilled(tester, 'Back to Profile');

      expect(find.byType(SellerVerificationSubmittedScreen), findsNothing);
      expect(find.byType(SellerVerificationScreen), findsOneWidget);
      expect(find.text('Under review'), findsOneWidget);
    });

    testWidgets('shows a 422 on the field it belongs to', (
      WidgetTester tester,
    ) async {
      await SellerVerificationHarness.pump(
        tester,
        tokenStore: tokenStore,
        pickImage: fakeVerificationPicker,
        handler: (RecordedRequest request) async {
          if (request.method != 'POST') {
            return sellerVerificationNotFoundResponse();
          }
          if (request.apiPath == '/seller-verification/documents') {
            return sellerVerificationDocumentUploadedResponse();
          }
          return sellerVerificationValidationResponse(
            errors: <String, Object>{
              'business_name': <String>['The business name field is required.'],
            },
          );
        },
      );
      await openSellerVerificationForm(tester, resubmission: false);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Business name'),
        'Rizal Farms',
      );
      await tapNext(tester);
      await uploadBothDocuments(tester);
      await tapNext(tester);
      await tapFilled(tester, 'Submit Application');

      // Back on the field, with the server's message beside it.
      expect(find.text('The business name field is required.'), findsOneWidget);
      expect(find.text('Review Your Information'), findsNothing);
      expect(
        find.widgetWithText(TextFormField, 'Business name'),
        findsOneWidget,
      );
    });

    testWidgets('shows a 409 as information, not a failure', (
      WidgetTester tester,
    ) async {
      // A record appears between opening the form and submitting — a second
      // device, or an administrator opening a review. The follow-up read proves
      // it.
      var reads = 0;
      await SellerVerificationHarness.pump(
        tester,
        tokenStore: tokenStore,
        pickImage: fakeVerificationPicker,
        handler: (RecordedRequest request) async {
          if (request.apiPath == '/seller-verification/documents') {
            return sellerVerificationDocumentUploadedResponse();
          }
          if (request.apiPath == '/seller-verification' &&
              request.method == 'POST') {
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
      await tapNext(tester);
      await uploadBothDocuments(tester);
      await tapNext(tester);
      await tapFilled(tester, 'Submit Application');

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
        pickImage: fakeVerificationPicker,
        handler: (RecordedRequest request) async {
          if (request.apiPath == '/seller-verification/documents') {
            return sellerVerificationDocumentUploadedResponse();
          }
          if (request.apiPath == '/seller-verification' &&
              request.method == 'POST') {
            return gate.future;
          }
          return sellerVerificationNotFoundResponse();
        },
      );
      await openSellerVerificationForm(tester, resubmission: false);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Business name'),
        'Rizal Farms',
      );
      await tapNext(tester);
      await uploadBothDocuments(tester);
      await tapNext(tester);
      final Finder submit = find.widgetWithText(
        FilledButton,
        'Submit Application',
      );
      await tester.ensureVisible(submit);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(submit);
      // One frame: enough to start the request, nowhere near enough to finish it.
      await tester.pump(const Duration(milliseconds: 10));

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

      expect(
        find.widgetWithText(TextFormField, 'Santos Cattle Co.'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextFormField, 'Mabalacat, Pampanga'),
        findsOneWidget,
      );
    });
  });

  group('documents', () {
    /// Opens the form and advances to the Documents step with a valid name.
    Future<SellerVerificationHarness> openDocumentsStep(
      WidgetTester tester, {
      required Future<http.Response> Function(RecordedRequest request) handler,
    }) async {
      final SellerVerificationHarness harness =
          await SellerVerificationHarness.pump(
            tester,
            tokenStore: tokenStore,
            pickImage: fakeVerificationPicker,
            handler: handler,
          );
      await openSellerVerificationForm(tester, resubmission: false);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Business name'),
        'Rizal Farms',
      );
      await tapNext(tester);
      return harness;
    }

    testWidgets('uploads each document as soon as it is chosen', (
      WidgetTester tester,
    ) async {
      final SellerVerificationHarness harness = await openDocumentsStep(
        tester,
        handler: (RecordedRequest request) async =>
            request.apiPath == '/seller-verification/documents'
            ? sellerVerificationDocumentUploadedResponse()
            : sellerVerificationNotFoundResponse(),
      );

      await tapDocumentPick(tester, 'Valid Government-Issued ID');
      await tapDocumentPick(tester, 'Selfie Holding Your ID');

      // One upload per chosen document, and the type is carried in the body —
      // two rows staged, never one image sent twice.
      final List<RecordedRequest> uploads = harness.recorded
          .where(
            (RecordedRequest r) =>
                r.apiPath == '/seller-verification/documents' &&
                r.method == 'POST',
          )
          .toList();
      expect(uploads, hasLength(2));
      expect(uploads.first.query, isEmpty);
      // Both slots are now persisted, so the Next action is live.
      final FilledButton next = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Next'),
      );
      expect(next.onPressed, isNotNull);
    });

    testWidgets('blocks Next until both documents are persisted', (
      WidgetTester tester,
    ) async {
      await openDocumentsStep(
        tester,
        handler: (RecordedRequest request) async =>
            request.apiPath == '/seller-verification/documents'
            ? sellerVerificationDocumentUploadedResponse()
            : sellerVerificationNotFoundResponse(),
      );

      // Nothing chosen yet.
      FilledButton next = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Next'),
      );
      expect(next.onPressed, isNull);
      expect(
        find.text('Both documents must be uploaded before you can continue.'),
        findsOneWidget,
      );

      // One of two is still not enough.
      await tapDocumentPick(tester, 'Valid Government-Issued ID');
      next = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Next'),
      );
      expect(next.onPressed, isNull);

      await tapDocumentPick(tester, 'Selfie Holding Your ID');
      next = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Next'),
      );
      expect(next.onPressed, isNotNull);
    });

    testWidgets('offers a retry when an upload fails, and never fakes success', (
      WidgetTester tester,
    ) async {
      await openDocumentsStep(
        tester,
        handler: (RecordedRequest request) async =>
            request.apiPath == '/seller-verification/documents'
            ? throw http.ClientException('connection refused')
            : sellerVerificationNotFoundResponse(),
      );

      await tapDocumentPick(tester, 'Valid Government-Issued ID');

      // The failure is stated; the slot is not shown as uploaded, and Next stays
      // disabled because the server never confirmed the document.
      expect(find.text('Upload failed'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
      expect(find.text('Uploaded'), findsNothing);
      final FilledButton next = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Next'),
      );
      expect(next.onPressed, isNull);
    });

    testWidgets('a cancelled picker changes nothing', (
      WidgetTester tester,
    ) async {
      final SellerVerificationHarness harness =
          await SellerVerificationHarness.pump(
            tester,
            tokenStore: tokenStore,
            pickImage: cancelledVerificationPicker,
            handler: (_) async => sellerVerificationNotFoundResponse(),
          );
      await openSellerVerificationForm(tester, resubmission: false);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Business name'),
        'Rizal Farms',
      );
      await tapNext(tester);

      await tapDocumentPick(tester, 'Valid Government-Issued ID');

      expect(
        harness.recorded.where(
          (RecordedRequest r) =>
              r.apiPath == '/seller-verification/documents',
        ),
        isEmpty,
        reason: 'a cancelled picker must not upload a document',
      );
      expect(find.text('Not selected'), findsNWidgets(2));
    });

    testWidgets('seeds the slots from a rejected record on resubmission', (
      WidgetTester tester,
    ) async {
      await SellerVerificationHarness.pump(
        tester,
        tokenStore: tokenStore,
        pickImage: fakeVerificationPicker,
        handler: (_) async => sellerVerificationResponse(
          verification: sellerVerificationJson(
            status: 'rejected',
            businessName: 'Santos Cattle Co.',
            hasIdDocument: true,
            hasSelfie: false,
          ),
        ),
      );
      await openSellerVerificationForm(tester, resubmission: true);

      // The record already holds the ID, so the Documents step reports it as
      // uploaded even though no local file was picked in this session, and the
      // selfie is still required.
      await tapNext(tester);

      // Scoped to the form: the rejected status screen behind it also renders an
      // "Uploaded" line for the documents the server holds.
      expect(
        find.descendant(
          of: find.byType(SellerVerificationFormScreen),
          matching: find.text('Uploaded'),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: find.byType(SellerVerificationFormScreen),
          matching: find.text('Not selected'),
        ),
        findsOneWidget,
      );
    });
  });
}
