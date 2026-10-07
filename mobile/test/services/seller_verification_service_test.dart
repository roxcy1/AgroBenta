import 'package:agrobenta_mobile/core/network/api_exception.dart';
import 'package:agrobenta_mobile/models/seller_verification.dart';
import 'package:agrobenta_mobile/services/seller_verification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/auth_fakes.dart';
import '../support/seller_verification_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;
  late SellerVerificationService service;

  /// Rebuilds the service over a new handler, keeping the same recording list.
  SellerVerificationService build(
    Future<http.Response> Function(RecordedRequest request) handler,
  ) => buildSellerVerificationService(tokenStore, handler, recorded: recorded);

  setUp(() {
    tokenStore = FakeTokenStore('1|mobile-token');
    recorded = <RecordedRequest>[];
    service = build((_) async => sellerVerificationResponse());
  });

  group('current()', () {
    test('reads the caller’s own verification', () async {
      final SellerVerification verification = await service.current();

      expect(recorded, hasLength(1));
      expect(recorded.single.method, 'GET');
      expect(recorded.single.apiPath, '/seller-verification/me');
      expect(recorded.single.authorization, 'Bearer 1|mobile-token');
      expect(verification.status, SellerVerificationStatus.submitted);
    });

    test(
      'sends no id, because the record is resolved from the session',
      () async {
        await service.current();

        // The path has no identifier at all. That is what makes "read your own
        // verification" impossible to point at somebody else's record.
        expect(recorded.single.path, isNot(contains(RegExp(r'/\d+'))));
      },
    );

    test('throws notFound when the user has never submitted', () async {
      service = build((_) async => sellerVerificationNotFoundResponse());

      await expectLater(
        service.current(),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiErrorKind.notFound,
          ),
        ),
      );
    });
  });

  group('submit()', () {
    test('posts to the submission endpoint', () async {
      service = build((_) async => sellerVerificationCreatedResponse());

      await service.submit(businessName: 'Rizal Farms');

      expect(recorded.single.method, 'POST');
      expect(recorded.single.apiPath, '/seller-verification');
    });

    test('sends only the fields the contract accepts', () async {
      service = build((_) async => sellerVerificationCreatedResponse());

      await service.submit(
        businessName: 'Rizal Farms',
        businessLocation: 'Mabalacat, Pampanga',
        businessDescription: 'Cattle and goats.',
        idDocumentRef: 'PHL-ID-88213',
      );

      expect(recorded.single.body.keys, <String>{
        'business_name',
        'business_location',
        'business_description',
        'id_document_ref',
      });
    });

    test(
      'omits blank optional fields rather than sending empty strings',
      () async {
        service = build((_) async => sellerVerificationCreatedResponse());

        await service.submit(
          businessName: 'Rizal Farms',
          businessLocation: '   ',
          businessDescription: '',
          idDocumentRef: null,
        );

        // An empty string would be stored and later read as "they said nothing"
        // rather than "they did not say". Only the required key is sent.
        expect(recorded.single.body, <String, dynamic>{
          'business_name': 'Rizal Farms',
        });
      },
    );

    test('trims values before sending', () async {
      service = build((_) async => sellerVerificationCreatedResponse());

      await service.submit(businessName: '  Rizal Farms  ');

      expect(recorded.single.body['business_name'], 'Rizal Farms');
    });

    test('never sends a server-owned field', () async {
      service = build((_) async => sellerVerificationCreatedResponse());

      await service.submit(
        businessName: 'Rizal Farms',
        businessLocation: 'Pampanga',
      );

      // The heart of the single-account model: a client cannot grant itself
      // seller capability, and cannot declare its own status. Neither key is
      // reachable from the method signature above.
      for (final String forbidden in <String>[
        'user_id',
        'status',
        'admin_note',
        'reviewed_by',
        'reviewed_at',
        'submitted_at',
        'role',
        'seller_capability',
      ]) {
        expect(
          recorded.single.body.containsKey(forbidden),
          isFalse,
          reason: '"$forbidden" must never be sent by the app',
        );
      }
    });

    test('surfaces a 409 as a conflict, not a validation error', () async {
      service = build((_) async => sellerVerificationConflictResponse());

      await expectLater(
        service.submit(businessName: 'Rizal Farms'),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.kind, 'kind', ApiErrorKind.conflict)
              .having(
                (ApiException e) => e.message,
                'message',
                contains('already open for review'),
              ),
        ),
      );
    });

    test('surfaces a 422 with its per-field messages', () async {
      service = build(
        (_) async => sellerVerificationValidationResponse(
          errors: <String, Object>{
            'business_name': <String>['The business name field is required.'],
          },
        ),
      );

      await expectLater(
        service.submit(businessName: ''),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException e) => e.kind,
                'kind',
                ApiErrorKind.validation,
              )
              .having(
                (ApiException e) => e.validationErrors['business_name'],
                'validationErrors',
                contains('The business name field is required.'),
              ),
        ),
      );
    });

    test('surfaces a 403 for an already-approved seller', () async {
      service = build((_) async => sellerVerificationForbiddenResponse());

      await expectLater(
        service.submit(businessName: 'Rizal Farms'),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiErrorKind.forbidden,
          ),
        ),
      );
    });

    test('parses the created record from a 201', () async {
      service = build(
        (_) async => sellerVerificationCreatedResponse(
          verification: sellerVerificationJson(id: 11, status: 'submitted'),
        ),
      );

      final SellerVerification created = await service.submit(
        businessName: 'Rizal Farms',
      );

      expect(created.id, 11);
      expect(created.status, SellerVerificationStatus.submitted);
    });
  });
}
