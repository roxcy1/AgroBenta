import 'package:agrobenta_mobile/core/constants/api_constants.dart';
import 'package:agrobenta_mobile/core/network/api_exception.dart';
import 'package:agrobenta_mobile/models/offer.dart';
import 'package:agrobenta_mobile/services/offer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/auth_fakes.dart';
import '../support/offer_fakes.dart';

/// The offer API surface, including the body and query allow-lists.
///
/// `buyer_id`, `seller_id`, `status` and `responded_at` have no parameter that
/// could reach a request body, and ownership-shaped query filters are refused
/// by the server. These tests assert the client never tries.
void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;
  late OfferService service;

  OfferService build(
    Future<http.Response> Function(RecordedRequest request) handler,
  ) => buildOfferService(tokenStore, handler, recorded: recorded);

  setUp(() {
    tokenStore = FakeTokenStore('1|mobile-token');
    recorded = <RecordedRequest>[];
    service = build((_) async => offersResponse());
  });

  group('list()', () {
    test(
      'gets the caller-scoped list with only the supplied filters',
      () async {
        final List<Offer> offers = await service.list(
          counterpartId: 3,
          status: OfferStatus.pending,
        );

        expect(offers, hasLength(1));
        expect(recorded.single.method, 'GET');
        expect(recorded.single.apiPath, OfferEndpoints.list);
        expect(recorded.single.authorization, 'Bearer 1|mobile-token');
        expect(recorded.single.query, <String, String>{
          'counterpart_id': '3',
          'status': 'pending',
        });
      },
    );

    test('sends no query parameters when no filter is chosen', () async {
      await service.list();

      expect(recorded.single.query, isEmpty);
    });

    test('parses an empty list', () async {
      service = build(
        (_) async => offersResponse(offers: <Map<String, dynamic>>[]),
      );

      expect(await service.list(), isEmpty);
    });

    test('surfaces the server validation error for a refused filter', () async {
      service = build(
        (_) async => offerValidationResponse(
          errors: <String, Object>{
            'buyer_id': <String>['The buyer id field is prohibited.'],
          },
        ),
      );

      await expectLater(
        service.list(),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException e) => e.kind,
                'kind',
                ApiErrorKind.validation,
              )
              .having(
                (ApiException e) => e.validationErrors['buyer_id'],
                'errors',
                isNotEmpty,
              ),
        ),
      );
    });
  });

  group('create()', () {
    test('posts exactly the three client-owned fields', () async {
      service = build((_) async => offerCreatedResponse());

      final Offer offer = await service.create(
        inquiryId: 5,
        listingId: 12,
        proposedAmount: '48000.00',
      );

      expect(offer.id, 1);
      expect(recorded.single.method, 'POST');
      expect(recorded.single.apiPath, OfferEndpoints.create);
      expect(recorded.single.body.keys.toSet(), <String>{
        'inquiry_id',
        'listing_id',
        'proposed_amount',
      });
      expect(recorded.single.body['inquiry_id'], 5);
      expect(recorded.single.body['listing_id'], 12);
      expect(recorded.single.body['proposed_amount'], '48000.00');
    });

    test('a 422 surfaces the field error and message', () async {
      service = build((_) async => offerValidationResponse());

      await expectLater(
        service.create(inquiryId: 5, listingId: 12, proposedAmount: '0.00'),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.statusCode, 'status', 422)
              .having(
                (ApiException e) =>
                    e.validationErrors['proposed_amount']?.first,
                'proposed_amount',
                'The proposed amount must be at least 0.01.',
              ),
        ),
      );
    });
  });

  group('actions', () {
    test('accept parses both the offer and the transaction', () async {
      service = build((_) async => offerAcceptedResponse());

      final OfferAcceptance result = await service.accept(1);

      expect(recorded.single.method, 'POST');
      expect(recorded.single.apiPath, OfferEndpoints.accept(1));
      expect(
        recorded.single.request.body,
        isEmpty,
        reason: 'the action body allow-list is empty',
      );
      expect(result.offer.status, OfferStatus.accepted);
      expect(result.transaction.totalAmount, '48000.00');
    });

    test(
      'decline posts to its own route and parses the updated offer',
      () async {
        service = build(
          (_) async =>
              offerUpdatedResponse(offer: offerJson(status: 'declined')),
        );

        final Offer offer = await service.decline(4);

        expect(recorded.single.apiPath, OfferEndpoints.decline(4));
        expect(offer.status, OfferStatus.declined);
      },
    );

    test(
      'withdraw posts to its own route and parses the updated offer',
      () async {
        service = build(
          (_) async =>
              offerUpdatedResponse(offer: offerJson(status: 'withdrawn')),
        );

        final Offer offer = await service.withdraw(4);

        expect(recorded.single.apiPath, OfferEndpoints.withdraw(4));
        expect(offer.status, OfferStatus.withdrawn);
      },
    );

    test('a 409 surfaces the server conflict message', () async {
      service = build(
        (_) async => offerConflictResponse(message: 'Already accepted.'),
      );

      await expectLater(
        service.accept(1),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.kind, 'kind', ApiErrorKind.conflict)
              .having(
                (ApiException e) => e.message,
                'message',
                'Already accepted.',
              ),
        ),
      );
    });
  });
}
