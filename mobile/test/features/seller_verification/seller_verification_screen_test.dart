import 'dart:async';

import 'package:agrobenta_mobile/features/seller_verification/view/seller_verification_form_screen.dart';
import 'package:agrobenta_mobile/features/seller_verification/view/seller_verification_screen.dart';
import 'package:agrobenta_mobile/features/seller_verification/view/seller_verification_submitted_screen.dart';
import 'package:agrobenta_mobile/widgets/local_image_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/seller_verification_app_harness.dart';
import '../../support/seller_verification_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;

  setUp(() => tokenStore = FakeTokenStore('1|mobile-token'));

  /// Taps a filled button after its scroll-to-visible animation completes.
  Future<void> tapFilled(WidgetTester tester, String label) async {
    final Finder target = find.widgetWithText(FilledButton, label);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    // There is no in-flight request before this tap, so settling here only waits
    // for the scroll animation; request spinners are handled by the bounded helper.
    await tester.pumpAndSettle();
    await tester.tap(target);
    await settleSellerVerification(tester);
  }

  /// Advances one step, supplying the required contact snapshots in this shared
  /// form-flow helper when no auth profile values were provided by a test.
  Future<void> tapNext(WidgetTester tester) async {
    for (final (String label, String value) in <(String, String)>[
      ('Phone number', '09171234567'),
      ('Address', 'Trinidad, Bohol'),
    ]) {
      final Finder field = find.widgetWithText(TextFormField, label);
      if (field.evaluate().isNotEmpty &&
          (tester.widget<TextFormField>(field).controller?.text.isEmpty ??
              true)) {
        await tester.enterText(field, value);
      }
    }
    await tapFilled(tester, 'Next');
  }

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
      expect(find.widgetWithText(FilledButton, 'Get Started'), findsOneWidget);
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
      expect(find.widgetWithText(FilledButton, 'Get Started'), findsNothing);
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
    testWidgets(
      'shows required applicant snapshots and optional business fields',
      (WidgetTester tester) async {
        await SellerVerificationHarness.pump(
          tester,
          tokenStore: tokenStore,
          accountName: 'Ana Reyes',
          handler: (_) async => sellerVerificationNotFoundResponse(),
        );
        await openSellerVerificationForm(tester, resubmission: false);

        expect(find.byType(SellerVerificationFormScreen), findsOneWidget);

        // Full name is read-only account data. Phone and address are required
        // application snapshots; business fields remain optional.
        expect(find.byType(TextFormField), findsNWidgets(6));
        expect(find.text('Full name'), findsOneWidget);
        expect(find.text('Phone number'), findsOneWidget);
        expect(find.text('Address'), findsOneWidget);
        expect(find.text('Business name'), findsOneWidget);
        expect(find.text('Business location'), findsOneWidget);
        expect(find.text('Business description'), findsOneWidget);
        expect(find.text('ID document reference'), findsNothing);
      },
    );

    testWidgets('requires a phone number and address before continuing', (
      WidgetTester tester,
    ) async {
      await SellerVerificationHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => sellerVerificationNotFoundResponse(),
      );
      await openSellerVerificationForm(tester, resubmission: false);

      final Finder next = find.widgetWithText(FilledButton, 'Next');
      await scrollSellerVerificationIntoView(tester, next);
      await tester.tap(next);
      await settleSellerVerification(tester);

      expect(find.text('Phone number is required.'), findsOneWidget);
      expect(find.text('Address is required.'), findsOneWidget);
      expect(find.text('Upload Required Documents'), findsNothing);
    });

    testWidgets('collects the Figure 19 documents on the Documents step', (
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
      expect(find.text('Proof of Address'), findsOneWidget);
      expect(find.text('Selfie Holding Your ID'), findsOneWidget);
      expect(find.text('Farm Photos'), findsOneWidget);
      expect(find.textContaining('Take Photo'), findsWidgets);
      // The ID image is never offered as the selfie — they are distinct.
      expect(find.textContaining('cannot be reused'), findsOneWidget);
    });

    testWidgets('a blank business name can still advance', (
      WidgetTester tester,
    ) async {
      await SellerVerificationHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => sellerVerificationNotFoundResponse(),
      );
      await openSellerVerificationForm(tester, resubmission: false);

      await tapNext(tester);

      expect(find.text('Upload Required Documents'), findsOneWidget);
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
      await scrollSellerVerificationIntoView(tester, back);
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
                r.method == 'POST' && r.apiPath == '/seller-verification',
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

    testWidgets(
      're-stages local documents after the server reports they are missing',
      (WidgetTester tester) async {
        int submissions = 0;
        final SellerVerificationHarness
        harness = await SellerVerificationHarness.pump(
          tester,
          tokenStore: tokenStore,
          pickImage: fakeVerificationPicker,
          handler: (RecordedRequest request) async {
            if (request.method == 'POST' &&
                request.apiPath == '/seller-verification/documents') {
              return sellerVerificationDocumentUploadedResponse();
            }
            if (request.method == 'POST' &&
                request.apiPath == '/seller-verification') {
              submissions++;
              if (submissions == 1) {
                return sellerVerificationValidationResponse(
                  message: 'Upload all required documents before submitting.',
                  errors: <String, Object>{
                    'id_document': <String>[
                      'Upload a clear photo of your government-issued ID.',
                    ],
                    'proof_of_address': <String>[
                      'Upload your proof of address.',
                    ],
                    'selfie': <String>['Upload a selfie holding the same ID.'],
                  },
                );
              }
              return sellerVerificationCreatedResponse(
                verification: sellerVerificationJson(status: 'submitted'),
              );
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

        expect(find.text('Upload Required Documents'), findsOneWidget);
        expect(find.text('Upload required'), findsNWidgets(3));
        expect(find.text('Upload again'), findsNWidgets(3));
        FilledButton next = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Next'),
        );
        expect(next.onPressed, isNull);

        for (int index = 0; index < 3; index++) {
          final Finder retry = find
              .widgetWithText(FilledButton, 'Upload again')
              .first;
          await scrollSellerVerificationIntoView(tester, retry);
          await tester.tap(retry);
          await settleSellerVerification(tester);
        }

        next = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Next'),
        );
        expect(next.onPressed, isNotNull);
        await tapNext(tester);
        await tapFilled(tester, 'Submit Application');

        expect(submissions, 2);
        expect(find.byType(SellerVerificationSubmittedScreen), findsOneWidget);
        expect(
          harness.recorded.where(
            (RecordedRequest request) =>
                request.method == 'POST' &&
                request.apiPath == '/seller-verification/documents',
          ),
          hasLength(6),
          reason: 'the three documents must be staged again after a 422',
        );
      },
    );

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
      await scrollSellerVerificationIntoView(tester, submit);
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
            phone: '09123456789',
            address: 'Barangay Poblacion, Trinidad, Bohol',
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
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Phone number'),
            )
            .controller!
            .text,
        '09123456789',
      );
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Address'),
            )
            .controller!
            .text,
        'Barangay Poblacion, Trinidad, Bohol',
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

      await uploadBothDocuments(tester);

      // One upload per chosen document, and the type is carried in the body —
      // never one image sent twice.
      final List<RecordedRequest> uploads = harness.recorded
          .where(
            (RecordedRequest r) =>
                r.apiPath == '/seller-verification/documents' &&
                r.method == 'POST',
          )
          .toList();
      expect(uploads, hasLength(3));
      expect(uploads.first.query, isEmpty);
      // All required slots are now persisted, so the Next action is live.
      final FilledButton next = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Next'),
      );
      expect(next.onPressed, isNotNull);
    });

    testWidgets('blocks Next until every required document is persisted', (
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
        find.text(
          'All required documents must be uploaded before you can continue.',
        ),
        findsOneWidget,
      );

      // Two of three is still not enough.
      await tapDocumentPick(tester, 'Valid Government-Issued ID');
      await tapDocumentPick(tester, 'Selfie Holding Your ID');
      next = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Next'),
      );
      expect(next.onPressed, isNull);

      await tapDocumentPick(tester, 'Proof of Address');
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
          (RecordedRequest r) => r.apiPath == '/seller-verification/documents',
        ),
        isEmpty,
        reason: 'a cancelled picker must not upload a document',
      );
      expect(find.text('Not selected'), findsNWidgets(3));
    });

    testWidgets('farm photos are optional, several, and removable', (
      WidgetTester tester,
    ) async {
      int uploaded = 0;
      final SellerVerificationHarness harness = await openDocumentsStep(
        tester,
        handler: (RecordedRequest request) async {
          if (request.method == 'DELETE') {
            return sellerVerificationDocumentDeletedResponse();
          }
          return request.apiPath == '/seller-verification/documents'
              ? sellerVerificationDocumentUploadedResponse(
                  type: 'farm_photo',
                  photoId: 'photo${++uploaded}',
                )
              : sellerVerificationNotFoundResponse();
        },
      );

      Future<void> addPhoto() async {
        final Finder add = find.text('Add Photo');
        await scrollSellerVerificationIntoView(tester, add);
        await tester.tap(add);
        await settleSellerVerification(tester);
      }

      await addPhoto();
      await addPhoto();
      expect(find.text('Photo 1'), findsOneWidget);
      expect(find.text('Photo 2'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove photo 1'));
      await settleSellerVerification(tester);

      expect(
        harness.recorded.last.apiPath,
        '/seller-verification/documents/farm_photo/photo1',
      );
      expect(find.text('Photo 2'), findsNothing);
      expect(find.text('Photo 1'), findsOneWidget);
    });

    testWidgets('a farm photo the server still holds stays until removed', (
      WidgetTester tester,
    ) async {
      await openDocumentsStep(
        tester,
        handler: (RecordedRequest request) async {
          if (request.method == 'DELETE') {
            return http.Response('{"message":"Server error"}', 500);
          }
          return request.apiPath == '/seller-verification/documents'
              ? sellerVerificationDocumentUploadedResponse(
                  type: 'farm_photo',
                  photoId: 'photo1',
                )
              : sellerVerificationNotFoundResponse();
        },
      );

      final Finder add = find.text('Add Photo');
      await scrollSellerVerificationIntoView(tester, add);
      await tester.tap(add);
      await settleSellerVerification(tester);

      await tester.tap(find.byTooltip('Remove photo 1'));
      await settleSellerVerification(tester);

      expect(find.text('Photo 1'), findsOneWidget);
      expect(
        find.text('Could not remove the photo. Please try again.'),
        findsOneWidget,
      );
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
            hasProofOfAddress: true,
          ),
        ),
      );
      await openSellerVerificationForm(tester, resubmission: true);

      // The rejected record's files remain available as historical previews,
      // but none are staged for this new application. Both prior documents must
      // be uploaded again; the missing selfie still needs to be selected too.
      await tapNext(tester);

      expect(
        find.descendant(
          of: find.byType(SellerVerificationFormScreen),
          matching: find.byType(LocalImagePreview),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(SellerVerificationFormScreen),
          matching: find.text('Upload required'),
        ),
        findsNWidgets(2),
      );
      expect(
        find.descendant(
          of: find.byType(SellerVerificationFormScreen),
          matching: find.text('Not selected'),
        ),
        findsOneWidget,
      );
      final FilledButton next = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Next'),
      );
      expect(next.onPressed, isNull);
    });
  });
}
