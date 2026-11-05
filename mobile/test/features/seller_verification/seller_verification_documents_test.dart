import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/core/network/api_exception.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_controller.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_scope.dart';
import 'package:agrobenta_mobile/features/seller_verification/state/seller_verification_controller.dart';
import 'package:agrobenta_mobile/features/seller_verification/state/seller_verification_documents_controller.dart';
import 'package:agrobenta_mobile/features/seller_verification/state/seller_verification_scope.dart';
import 'package:agrobenta_mobile/features/seller_verification/state/seller_verification_documents_state.dart';
import 'package:agrobenta_mobile/features/seller_verification/widgets/seller_verification_document_card.dart';
import 'package:agrobenta_mobile/features/seller_verification/view/seller_verification_form_screen.dart';
import 'package:agrobenta_mobile/models/seller_verification.dart';
import 'package:agrobenta_mobile/repositories/seller_verification_repository.dart';
import 'package:agrobenta_mobile/services/seller_verification_service.dart';
import 'package:agrobenta_mobile/widgets/local_image_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';

import '../../support/auth_fakes.dart';
import '../../support/seller_verification_app_harness.dart';
import '../../support/seller_verification_fakes.dart';

typedef _Upload = Future<void> Function(XFile file);
typedef _Fetch = Future<Uint8List?> Function(VerificationDocumentType type);

class _DocumentRepository extends SellerVerificationRepository {
  _DocumentRepository(this.upload, {this.fetch, this.delete})
    : super(_unusedRepository());

  final _Upload upload;
  final _Fetch? fetch;
  final Future<void> Function(VerificationDocumentType type)? delete;

  static SellerVerificationService _unusedRepository() {
    final ApiClient client = ApiClient(
      tokenStorage: FakeTokenStore(),
      httpClient: MockClient(
        (_) async => throw StateError('Unexpected HTTP request.'),
      ),
    );
    return SellerVerificationService(client);
  }

  @override
  Future<void> uploadDocument({
    required VerificationDocumentType type,
    required XFile file,
    void Function(int sent, int total)? onProgress,
  }) => upload(file);

  @override
  Future<Uint8List?> fetchDocument(VerificationDocumentType type) =>
      fetch?.call(type) ?? Future<Uint8List?>.value(null);

  @override
  Future<void> deleteDocument(VerificationDocumentType type) =>
      delete?.call(type) ?? Future<void>.value();
}

void main() {
  final VerificationDocumentType type =
      VerificationDocumentType.idDocumentFront;

  XFile image(String name) => XFile.fromData(
    kFakeVerificationImageBytes,
    name: name,
    mimeType: 'image/png',
  );

  SellerVerification existingVerification({
    bool hasIdDocument = true,
    bool hasProofOfAddress = true,
    bool hasSelfie = true,
  }) => SellerVerification.fromJson(
    sellerVerificationJson(
      status: 'rejected',
      hasIdDocument: hasIdDocument,
      hasProofOfAddress: hasProofOfAddress,
      hasSelfie: hasSelfie,
    ),
  );

  group('document upload state', () {
    test(
      'requires an explicit back choice and clears a staged back safely',
      () async {
        final List<VerificationDocumentType> deleted =
            <VerificationDocumentType>[];
        final SellerVerificationDocumentsController controller =
            SellerVerificationDocumentsController(
              _DocumentRepository(
                (_) async {},
                delete: (VerificationDocumentType type) async {
                  deleted.add(type);
                },
              ),
            );
        addTearDown(controller.dispose);

        expect(controller.state.hasNoBackImage, isNull);
        expect(controller.state.allRequiredUploaded, isFalse);
        await controller.pickAndUpload(
          type: VerificationDocumentType.idDocumentBack,
          file: image('back.png'),
        );
        await controller.chooseBackImage(hasNoBackImage: true);

        expect(deleted, <VerificationDocumentType>[
          VerificationDocumentType.idDocumentBack,
        ]);
        expect(
          controller.state.idDocumentBack.status,
          VerificationDocumentStatus.empty,
        );
        expect(controller.state.hasNoBackImage, isTrue);

        await controller.chooseBackImage(hasNoBackImage: false);
        expect(controller.state.hasNoBackImage, isFalse);
        expect(controller.state.allRequiredUploaded, isFalse);
      },
    );

    test('retains the selected file after a successful upload', () async {
      final XFile selected = image('selected.png');
      final SellerVerificationDocumentsController controller =
          SellerVerificationDocumentsController(
            _DocumentRepository((_) async {}),
          );
      addTearDown(controller.dispose);

      await controller.pickAndUpload(type: type, file: selected);

      final VerificationDocument document = controller.state.forType(type);
      expect(document.status, VerificationDocumentStatus.uploaded);
      expect(identical(document.file, selected), isTrue);
      expect(document.progress, isNull);
      expect(document.error, isNull);
    });

    test('a failed replacement keeps the replacement file retryable', () async {
      final XFile original = image('original.png');
      final XFile replacement = image('replacement.png');
      int attempts = 0;
      final SellerVerificationDocumentsController controller =
          SellerVerificationDocumentsController(
            _DocumentRepository((XFile file) async {
              attempts++;
              if (file.name == replacement.name && attempts == 2) {
                throw StateError('Upload failed.');
              }
            }),
          );
      addTearDown(controller.dispose);

      await controller.pickAndUpload(type: type, file: original);
      await controller.pickAndUpload(type: type, file: replacement);

      VerificationDocument document = controller.state.forType(type);
      expect(document.status, VerificationDocumentStatus.failed);
      expect(identical(document.file, replacement), isTrue);
      expect(document.error, 'Upload failed. Please try again.');
      expect(document.progress, isNull);

      await controller.retry(type);

      document = controller.state.forType(type);
      expect(document.status, VerificationDocumentStatus.uploaded);
      expect(identical(document.file, replacement), isTrue);
      expect(attempts, 3);
    });

    test(
      'a missing-staging response marks the local file for re-upload',
      () async {
        final XFile selected = image('id_document.png');
        final SellerVerificationDocumentsController controller =
            SellerVerificationDocumentsController(
              _DocumentRepository((_) async {}),
            );
        addTearDown(controller.dispose);

        await controller.pickAndUpload(type: type, file: selected);
        controller.markDocumentsForReupload(<VerificationDocumentType>[type]);

        VerificationDocument document = controller.state.forType(type);
        expect(document.status, VerificationDocumentStatus.needsUpload);
        expect(identical(document.file, selected), isTrue);
        expect(document.isUploaded, isFalse);
        expect(controller.state.allRequiredUploaded, isFalse);

        await controller.retry(type);

        document = controller.state.forType(type);
        expect(document.status, VerificationDocumentStatus.uploaded);
        expect(identical(document.file, selected), isTrue);
      },
    );

    test(
      'seeded uploaded documents fetch authenticated bytes by document type',
      () async {
        final FakeTokenStore tokenStore = FakeTokenStore('1|preview-token');
        final List<RecordedRequest> requests = <RecordedRequest>[];
        final SellerVerificationRepository repository =
            buildSellerVerificationRepository(
              tokenStore,
              (RecordedRequest request) async => http.Response.bytes(
                kFakeVerificationImageBytes,
                200,
                headers: <String, String>{'content-type': 'image/png'},
              ),
              recorded: requests,
            );
        final SellerVerificationDocumentsController controller =
            SellerVerificationDocumentsController(repository);
        addTearDown(controller.dispose);

        await controller.seedFrom(existingVerification());

        expect(
          requests.map((RecordedRequest request) => request.apiPath),
          containsAll(<String>[
            '/seller-verification/documents/id_document_front',
            '/seller-verification/documents/proof_of_address',
            '/seller-verification/documents/selfie',
          ]),
        );
        expect(requests, hasLength(3));
        expect(
          requests.every((RecordedRequest r) => r.method == 'GET'),
          isTrue,
        );
        expect(
          requests.every(
            (RecordedRequest r) => r.authorization == 'Bearer 1|preview-token',
          ),
          isTrue,
        );
        for (final VerificationDocument document in controller.state.all) {
          expect(document.status, VerificationDocumentStatus.needsUpload);
          expect(document.hasPreviousRecordDocument, isTrue);
          expect(
            document.previewStatus,
            VerificationDocumentPreviewStatus.loaded,
          );
          expect(document.previewBytes, kFakeVerificationImageBytes);
        }
        expect(controller.state.allRequiredUploaded, isFalse);
      },
    );

    test(
      'local files take priority and supersede an in-flight remote preview',
      () async {
        final Completer<Uint8List?> remote = Completer<Uint8List?>();
        int fetches = 0;
        final XFile replacement = image('replacement.png');
        final SellerVerificationDocumentsController controller =
            SellerVerificationDocumentsController(
              _DocumentRepository(
                (_) async {},
                fetch: (_) {
                  fetches++;
                  return remote.future;
                },
              ),
            );
        addTearDown(controller.dispose);

        final Future<void> seed = controller.seedFrom(
          existingVerification(hasProofOfAddress: false, hasSelfie: false),
        );
        expect(
          controller.state
              .forType(VerificationDocumentType.idDocument)
              .previewStatus,
          VerificationDocumentPreviewStatus.loading,
        );

        await controller.pickAndUpload(
          type: VerificationDocumentType.idDocument,
          file: replacement,
        );
        await controller.loadPreview(VerificationDocumentType.idDocument);
        remote.complete(kFakeVerificationImageBytes);
        await seed;

        final VerificationDocument document = controller.state.forType(
          VerificationDocumentType.idDocument,
        );
        expect(fetches, 1);
        expect(document.status, VerificationDocumentStatus.uploaded);
        expect(identical(document.file, replacement), isTrue);
        expect(document.previewBytes, isNull);
      },
    );

    test('repeated preview requests share the in-flight fetch', () async {
      final Completer<Uint8List?> response = Completer<Uint8List?>();
      int fetches = 0;
      final SellerVerificationDocumentsController controller =
          SellerVerificationDocumentsController(
            _DocumentRepository(
              (_) async {},
              fetch: (_) {
                fetches++;
                return response.future;
              },
            ),
          );
      addTearDown(controller.dispose);

      final Future<void> seed = controller.seedFrom(
        existingVerification(hasProofOfAddress: false, hasSelfie: false),
      );
      // Seeding already began one retrieval. A rebuild/re-entry sees loading
      // and must reuse it rather than starting another request.
      final Future<void> first = controller.loadPreview(
        VerificationDocumentType.idDocument,
      );
      final Future<void> second = controller.loadPreview(
        VerificationDocumentType.idDocument,
      );
      expect(fetches, 1);
      response.complete(kFakeVerificationImageBytes);
      await Future.wait<void>(<Future<void>>[seed, first, second]);
      expect(
        controller.state
            .forType(VerificationDocumentType.idDocument)
            .previewStatus,
        VerificationDocumentPreviewStatus.loaded,
      );
    });

    test(
      'a missing historical preview keeps the new application upload-required',
      () async {
        final SellerVerificationDocumentsController controller =
            SellerVerificationDocumentsController(
              _DocumentRepository((_) async {}, fetch: (_) async => null),
            );
        addTearDown(controller.dispose);

        await controller.seedFrom(
          existingVerification(hasProofOfAddress: false, hasSelfie: false),
        );

        final VerificationDocument document = controller.state.forType(
          VerificationDocumentType.idDocument,
        );
        expect(document.status, VerificationDocumentStatus.needsUpload);
        expect(document.hasPreviousRecordDocument, isTrue);
        expect(
          document.previewStatus,
          VerificationDocumentPreviewStatus.missing,
        );
        expect(document.previewBytes, isNull);
      },
    );

    test(
      '401 clears the token and does not offer an unsafe preview retry',
      () async {
        final FakeTokenStore tokenStore = FakeTokenStore('1|expired-token');
        final List<RecordedRequest> requests = <RecordedRequest>[];
        final SellerVerificationRepository repository =
            buildSellerVerificationRepository(
              tokenStore,
              (_) async => http.Response('"Unauthenticated."', 401),
              recorded: requests,
            );
        final SellerVerificationDocumentsController controller =
            SellerVerificationDocumentsController(repository);
        addTearDown(controller.dispose);

        await controller.seedFrom(
          existingVerification(hasProofOfAddress: false, hasSelfie: false),
        );

        final VerificationDocument document = controller.state.forType(
          VerificationDocumentType.idDocument,
        );
        expect(tokenStore.token, isNull);
        expect(document.status, VerificationDocumentStatus.needsUpload);
        expect(
          document.previewStatus,
          VerificationDocumentPreviewStatus.failed,
        );
        expect(document.previewRetryable, isFalse);
        expect(requests.single.authorization, 'Bearer 1|expired-token');
      },
    );

    test(
      'a failed historical preview can be retried without satisfying staging',
      () async {
        int fetches = 0;
        final SellerVerificationDocumentsController controller =
            SellerVerificationDocumentsController(
              _DocumentRepository(
                (_) async {},
                fetch: (_) async {
                  fetches++;
                  if (fetches == 1) {
                    throw const ApiException.network(
                      message: 'Network unavailable.',
                    );
                  }
                  return kFakeVerificationImageBytes;
                },
              ),
            );
        addTearDown(controller.dispose);

        await controller.seedFrom(
          existingVerification(hasProofOfAddress: false, hasSelfie: false),
        );
        VerificationDocument document = controller.state.forType(
          VerificationDocumentType.idDocument,
        );
        expect(document.status, VerificationDocumentStatus.needsUpload);
        expect(
          document.previewStatus,
          VerificationDocumentPreviewStatus.failed,
        );
        expect(document.previewRetryable, isTrue);

        await controller.loadPreview(VerificationDocumentType.idDocument);

        document = controller.state.forType(
          VerificationDocumentType.idDocument,
        );
        expect(document.status, VerificationDocumentStatus.needsUpload);
        expect(
          document.previewStatus,
          VerificationDocumentPreviewStatus.loaded,
        );
        expect(fetches, 2);
      },
    );

    test(
      'account reset and disposal prevent old bytes from being reused',
      () async {
        final Completer<Uint8List?> response = Completer<Uint8List?>();
        final SellerVerificationDocumentsController controller =
            SellerVerificationDocumentsController(
              _DocumentRepository((_) async {}, fetch: (_) => response.future),
            );

        final Future<void> oldAccount = controller.seedFrom(
          existingVerification(hasProofOfAddress: false, hasSelfie: false),
        );
        controller.resetForAccountChange();
        response.complete(kFakeVerificationImageBytes);
        await oldAccount;

        expect(controller.state.allRequiredUploaded, isFalse);
        expect(
          controller.state
              .forType(VerificationDocumentType.idDocument)
              .previewBytes,
          isNull,
        );

        final Completer<Uint8List?> duringDispose = Completer<Uint8List?>();
        final SellerVerificationDocumentsController disposedController =
            SellerVerificationDocumentsController(
              _DocumentRepository(
                (_) async {},
                fetch: (_) => duringDispose.future,
              ),
            );
        final Future<void> pending = disposedController.seedFrom(
          existingVerification(hasProofOfAddress: false, hasSelfie: false),
        );
        disposedController.dispose();
        duringDispose.complete(kFakeVerificationImageBytes);
        await pending;
        controller.dispose();
      },
    );
  });

  group('document card preview', () {
    Widget card(VerificationDocument document) => MaterialApp(
      home: Scaffold(
        body: SellerVerificationDocumentCard(
          title: 'Government-Issued ID',
          instruction: 'Instruction',
          qualityGuidance: 'Quality guidance',
          document: document,
          onPick: () {},
          onRemove: () {},
          onRetry: () {},
          onRetryPreview: () {},
        ),
      ),
    );

    testWidgets('uses the byte-based preview path for a local image', (
      WidgetTester tester,
    ) async {
      final XFile file = image('web-compatible.png');

      await tester.pumpWidget(
        card(
          VerificationDocument(
            type: type,
            status: VerificationDocumentStatus.uploaded,
            file: file,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final LocalImagePreview preview = tester.widget<LocalImagePreview>(
        find.byType(LocalImagePreview),
      );
      expect(identical(preview.file, file), isTrue);
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Uploaded'), findsOneWidget);
    });

    testWidgets('uses the existing uploaded placeholder without a local file', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        card(
          const VerificationDocument(
            type: VerificationDocumentType.idDocument,
            status: VerificationDocumentStatus.uploaded,
          ),
        ),
      );

      expect(find.byType(LocalImagePreview), findsNothing);
      expect(find.text('Uploaded'), findsNWidgets(2));
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets(
      'prefills required contact snapshots from the account profile',
      (WidgetTester tester) async {
        final FakeTokenStore tokenStore = FakeTokenStore('1|profile-token');
        final AuthController authController = AuthController(
          buildAuthRepository(
            tokenStore,
            (_) async => http.Response(
              jsonEncode(
                successEnvelope(
                  data: userJson(
                    phone: '09445556666',
                    location: 'San Isidro, Trinidad',
                  ),
                ),
              ),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            ),
          ),
        );
        final SellerVerificationController verificationController =
            controllerReturning(null);
        addTearDown(authController.dispose);
        addTearDown(verificationController.dispose);
        await authController.restoreSession();
        await verificationController.load();

        await tester.pumpWidget(
          AuthScope(
            controller: authController,
            child: SellerVerificationScope(
              repository: _DocumentRepository((_) async {}),
              controller: verificationController,
              child: const MaterialApp(
                home: SellerVerificationFormScreen(isResubmission: false),
              ),
            ),
          ),
        );

        expect(
          tester
              .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Phone number'),
              )
              .controller!
              .text,
          '09445556666',
        );
        expect(
          tester
              .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Address'),
              )
              .controller!
              .text,
          'San Isidro, Trinidad',
        );
      },
    );

    testWidgets('renders remotely retrieved bytes in Image.memory', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        card(
          VerificationDocument(
            type: type,
            status: VerificationDocumentStatus.uploaded,
            previewStatus: VerificationDocumentPreviewStatus.loaded,
            previewBytes: kFakeVerificationImageBytes,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LocalImagePreview), findsNothing);
      final Image imageWidget = tester.widget<Image>(find.byType(Image));
      expect(imageWidget.image, isA<MemoryImage>());
      expect(find.text('Uploaded'), findsOneWidget);
    });

    testWidgets('shows a missing-file message for a 404 preview', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        card(
          const VerificationDocument(
            type: VerificationDocumentType.idDocument,
            status: VerificationDocumentStatus.uploaded,
            previewStatus: VerificationDocumentPreviewStatus.missing,
          ),
        ),
      );

      expect(find.text('This document is not available.'), findsOneWidget);
      expect(find.text('Uploaded'), findsOneWidget);
    });

    testWidgets('shows retry for recoverable preview failures', (
      WidgetTester tester,
    ) async {
      int retries = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SellerVerificationDocumentCard(
              title: 'Government-Issued ID',
              instruction: 'Instruction',
              qualityGuidance: 'Quality guidance',
              document: const VerificationDocument(
                type: VerificationDocumentType.idDocument,
                status: VerificationDocumentStatus.uploaded,
                previewStatus: VerificationDocumentPreviewStatus.failed,
                previewError: 'Network unavailable.',
                previewRetryable: true,
              ),
              onPick: () {},
              onRemove: () {},
              onRetry: () {},
              onRetryPreview: () => retries++,
            ),
          ),
        ),
      );

      expect(find.text('Network unavailable.'), findsOneWidget);
      await tester.tap(find.text('Retry preview'));
      expect(retries, 1);
    });

    testWidgets(
      'prefills first-time contact snapshots from the signed-in profile',
      (WidgetTester tester) async {
        final FakeTokenStore tokenStore = FakeTokenStore('1|profile-token');
        final AuthController authController = AuthController(
          buildAuthRepository(
            tokenStore,
            (_) async => http.Response(
              jsonEncode(
                successEnvelope(
                  data: userJson(
                    phone: '09445556666',
                    location: 'San Isidro, Trinidad',
                  ),
                ),
              ),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            ),
          ),
        );
        final SellerVerificationController verificationController =
            controllerReturning(null);
        addTearDown(authController.dispose);
        addTearDown(verificationController.dispose);
        await authController.restoreSession();
        await verificationController.load();

        await tester.pumpWidget(
          AuthScope(
            controller: authController,
            child: SellerVerificationScope(
              repository: _DocumentRepository((_) async {}),
              controller: verificationController,
              child: const MaterialApp(
                home: SellerVerificationFormScreen(isResubmission: false),
              ),
            ),
          ),
        );

        expect(
          tester
              .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Phone number'),
              )
              .controller!
              .text,
          '09445556666',
        );
        expect(
          tester
              .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Address'),
              )
              .controller!
              .text,
          'San Isidro, Trinidad',
        );
      },
    );

    testWidgets(
      'clears remote previews when the authenticated account changes',
      (WidgetTester tester) async {
        final FakeTokenStore tokenStore = FakeTokenStore('1|account-token');
        int userId = 7;
        final AuthController authController = AuthController(
          buildAuthRepository(
            tokenStore,
            (_) async => http.Response(
              jsonEncode(
                successEnvelope(
                  data: userJson(
                    id: userId,
                    phone: userId == 7 ? '07111111111' : '08222222222',
                    location: userId == 7
                        ? 'Old profile address'
                        : 'New profile address',
                  ),
                ),
              ),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            ),
          ),
        );
        final SellerVerificationController verificationController =
            controllerReturning(
              sellerVerificationJson(
                status: 'rejected',
                hasIdDocument: true,
                hasProofOfAddress: false,
                hasSelfie: false,
              ),
            );
        final _DocumentRepository documentsRepository = _DocumentRepository(
          (_) async {},
          fetch: (_) async => kFakeVerificationImageBytes,
        );
        addTearDown(authController.dispose);
        addTearDown(verificationController.dispose);
        await authController.restoreSession();
        await verificationController.load();

        await tester.pumpWidget(
          AuthScope(
            controller: authController,
            child: SellerVerificationScope(
              repository: documentsRepository,
              controller: verificationController,
              child: const MaterialApp(
                home: SellerVerificationFormScreen(isResubmission: true),
              ),
            ),
          ),
        );
        expect(
          tester
              .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Phone number'),
              )
              .controller!
              .text,
          '09171234567',
          reason: 'resubmission uses the previous verification snapshot',
        );
        expect(
          tester
              .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Address'),
              )
              .controller!
              .text,
          'Trinidad, Bohol',
        );
        final Finder next = find.widgetWithText(FilledButton, 'Next');
        await scrollSellerVerificationIntoView(tester, next);
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(find.byType(Image), findsOneWidget);

        userId = 8;
        await authController.restoreSession();
        await tester.pumpAndSettle();

        expect(find.byType(Image), findsNothing);
        expect(find.text('Not selected'), findsNWidgets(3));
        final Finder back = find.widgetWithText(OutlinedButton, 'Back');
        await scrollSellerVerificationIntoView(tester, back);
        await tester.tap(back);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Phone number'),
              )
              .controller!
              .text,
          '08222222222',
        );
        expect(
          tester
              .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Address'),
              )
              .controller!
              .text,
          'New profile address',
        );
      },
    );

    testWidgets('falls back when fetched image bytes cannot be decoded', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        card(
          VerificationDocument(
            type: type,
            status: VerificationDocumentStatus.uploaded,
            previewStatus: VerificationDocumentPreviewStatus.loaded,
            previewBytes: Uint8List.fromList(<int>[1, 2, 3]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.text('This document could not be displayed.'),
        findsOneWidget,
      );
    });

    testWidgets('falls back when local XFile bytes cannot be decoded', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        card(
          VerificationDocument(
            type: type,
            status: VerificationDocumentStatus.uploaded,
            file: XFile.fromData(
              Uint8List.fromList(<int>[1, 2, 3]),
              name: 'invalid.png',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('No image selected'), findsOneWidget);
    });
  });
}
