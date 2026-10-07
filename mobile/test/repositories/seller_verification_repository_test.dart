import 'package:agrobenta_mobile/core/network/api_exception.dart';
import 'package:agrobenta_mobile/models/seller_verification.dart';
import 'package:agrobenta_mobile/repositories/seller_verification_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/auth_fakes.dart';
import '../support/seller_verification_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;

  SellerVerificationRepository build(
    Future<http.Response> Function(RecordedRequest request) handler,
  ) => buildSellerVerificationRepository(tokenStore, handler);

  setUp(() => tokenStore = FakeTokenStore('1|mobile-token'));

  group('current()', () {
    test('returns null when the user has never submitted', () async {
      // A 404 here is the normal state for most buyers, not a failure. It must
      // not reach the screen as an error.
      final SellerVerificationRepository repository = build(
        (_) async => sellerVerificationNotFoundResponse(),
      );

      expect(await repository.current(), isNull);
    });

    test('returns the record when there is one', () async {
      final SellerVerificationRepository repository = build(
        (_) async => sellerVerificationResponse(
          verification: sellerVerificationJson(id: 6, status: 'approved'),
        ),
      );

      final SellerVerification? verification = await repository.current();

      expect(verification, isNotNull);
      expect(verification!.id, 6);
      expect(verification.isApproved, isTrue);
    });

    test(
      'propagates a transport failure instead of reporting "never applied"',
      () async {
        // Collapsing every error into null would tell a seller with a flaky
        // connection that they had never applied, which is a lie that costs them an
        // application.
        final SellerVerificationRepository repository = build(
          (_) async => throw http.ClientException('connection refused'),
        );

        await expectLater(
          repository.current(),
          throwsA(
            isA<ApiException>().having(
              (ApiException e) => e.kind,
              'kind',
              ApiErrorKind.network,
            ),
          ),
        );
      },
    );

    test('propagates a 403 rather than swallowing it', () async {
      final SellerVerificationRepository repository = build(
        (_) async => sellerVerificationForbiddenResponse(),
      );

      await expectLater(
        repository.current(),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiErrorKind.forbidden,
          ),
        ),
      );
    });
  });

  group('submit()', () {
    test('returns the created record', () async {
      final SellerVerificationRepository repository = build(
        (_) async => sellerVerificationCreatedResponse(
          verification: sellerVerificationJson(id: 8),
        ),
      );

      final SellerVerification created = await repository.submit(
        businessName: 'Rizal Farms',
      );

      expect(created.id, 8);
    });

    test('passes a 409 through untouched', () async {
      // The repository deliberately does not translate: the message and kind are
      // the screen's to present, and rewriting them here would be a second place
      // for the wording to drift.
      final SellerVerificationRepository repository = build(
        (_) async => sellerVerificationConflictResponse(),
      );

      await expectLater(
        repository.submit(businessName: 'Rizal Farms'),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiErrorKind.conflict,
          ),
        ),
      );
    });
  });
}
