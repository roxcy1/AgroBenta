import 'package:agrobenta_mobile/core/constants/api_constants.dart';
import 'package:agrobenta_mobile/core/network/api_exception.dart';
import 'package:agrobenta_mobile/models/inquiry.dart';
import 'package:agrobenta_mobile/services/inquiry_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/auth_fakes.dart';
import '../support/inquiry_fakes.dart';

/// The one write path this feature has, and the body it sends.
///
/// The heart of these tests is the allow-list: no path through the service may
/// produce a body containing `buyer_id`, `seller_id` or `status` — the three
/// the server marks `prohibited` — and the body must be exactly
/// [InquiryEndpoints.writableFields] when everything is filled in.
void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;
  late InquiryService service;

  /// Rebuilds the service over a new handler, keeping the same recording list.
  InquiryService build(
    Future<http.Response> Function(RecordedRequest request) handler,
  ) => buildInquiryService(tokenStore, handler, recorded: recorded);

  setUp(() {
    tokenStore = FakeTokenStore('1|mobile-token');
    recorded = <RecordedRequest>[];
    service = build((_) async => inquiryCreatedResponse());
  });

  group('create()', () {
    test('posts to the inquiry endpoint with the bearer token', () async {
      await service.create(listingId: 12, message: 'Still available?');

      expect(recorded, hasLength(1));
      expect(recorded.single.method, 'POST');
      expect(recorded.single.apiPath, InquiryEndpoints.create);
      expect(recorded.single.authorization, 'Bearer 1|mobile-token');
    });

    test('sends exactly the writable fields when all are supplied', () async {
      await service.create(
        listingId: 12,
        message: 'Is this one still available?',
        subject: 'General Inquiry',
        purchaseInterest: true,
        transactionMethod: InquiryTransactionMethod.directDeal,
        deliveryMethod: InquiryDeliveryMethod.arrangeDelivery,
        deliveryFee: '1500.00',
        contactMethod: InquiryContactMethod.inAppMessage,
        preferredSchedule: DateTime(2026, 10, 25),
      );

      expect(
        recorded.single.body.keys.toSet(),
        InquiryEndpoints.writableFields.toSet(),
        reason:
            'the body is the allow-list itself — buyer_id, seller_id and '
            'status are server-owned and must never appear',
      );
      expect(recorded.single.body['listing_id'], 12);
      expect(recorded.single.body['message'], 'Is this one still available?');
      expect(recorded.single.body['subject'], 'General Inquiry');
      expect(recorded.single.body['purchase_interest'], isTrue);
      expect(recorded.single.body['transaction_method'], 'direct_deal');
      expect(recorded.single.body['delivery_method'], 'arrange_delivery');
      expect(recorded.single.body['delivery_fee'], '1500.00');
      expect(recorded.single.body['contact_method'], 'in_app_message');
      expect(
        recorded.single.body['preferred_schedule'],
        '2026-10-25',
        reason: 'a date column round-trips as yyyy-MM-dd, not a timestamp',
      );
    });

    test('omits preferences that were never filled in', () async {
      await service.create(
        listingId: 12,
        message: 'Just a question.',
        purchaseInterest: false,
      );

      // `purchase_interest` is answered by the form every time, so it is sent
      // even when false — false and absent are different statements. The rest
      // were never chosen and must not be invented as empty strings.
      expect(recorded.single.body, <String, dynamic>{
        'listing_id': 12,
        'message': 'Just a question.',
        'purchase_interest': false,
      });
    });

    test('omits blank optionals rather than sending empty strings', () async {
      await service.create(
        listingId: 12,
        message: 'Just a question.',
        subject: '   ',
        purchaseInterest: true,
        deliveryFee: '',
      );

      expect(recorded.single.body.containsKey('subject'), isFalse);
      expect(recorded.single.body.containsKey('delivery_fee'), isFalse);
      expect(recorded.single.body.keys.toSet(), <String>{
        'listing_id',
        'message',
        'purchase_interest',
      });
    });

    test('trims the message and the delivery fee before sending', () async {
      await service.create(
        listingId: 12,
        message: '  Is this one still available?  ',
        purchaseInterest: true,
        deliveryFee: ' 1500.00 ',
      );

      expect(recorded.single.body['message'], 'Is this one still available?');
      expect(recorded.single.body['delivery_fee'], '1500.00');
    });

    test('server-owned fields have no path into the body', () async {
      // Every parameter that could carry them, filled — and the keys still
      // absent, because no parameter maps to them. The server marks all three
      // `prohibited`, so sending one would be a client bug, not a courtesy.
      await service.create(
        listingId: 12,
        message: 'Hello',
        purchaseInterest: true,
        subject: 'General Inquiry',
        transactionMethod: InquiryTransactionMethod.arrangeDelivery,
        deliveryMethod: InquiryDeliveryMethod.buyerPickup,
        deliveryFee: '0',
        contactMethod: InquiryContactMethod.inAppMessage,
      );

      for (final String forbidden in <String>[
        'buyer_id',
        'seller_id',
        'status',
      ]) {
        expect(
          recorded.single.body.containsKey(forbidden),
          isFalse,
          reason: '$forbidden is server-owned and must be unreachable',
        );
      }
    });

    test('parses the created record from the 201', () async {
      service = build(
        (_) async => inquiryCreatedResponse(
          inquiry: inquiryJson(id: 9, message: 'Stored message.'),
        ),
      );

      final Inquiry inquiry = await service.create(
        listingId: 12,
        message: 'Stored message.',
        purchaseInterest: true,
      );

      expect(inquiry.id, 9);
      expect(inquiry.message, 'Stored message.');
      expect(inquiry.listing?.id, 12);
      expect(inquiry.contactMethod, InquiryContactMethod.inAppMessage);
      expect(inquiry.deliveryFee, '1500.00');
      expect(inquiry.preferredSchedule, DateTime(2026, 10, 25));
      expect(inquiry.createdAt, isNotNull);
    });

    test('surfaces a 422 with its per-field messages', () async {
      service = build(
        (_) async => inquiryValidationResponse(
          errors: <String, Object>{
            'message': <String>['The message must not be greater than 500 characters.'],
          },
        ),
      );

      await expectLater(
        service.create(listingId: 12, message: 'x' * 501, purchaseInterest: true),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.kind, 'kind', ApiErrorKind.validation)
              .having(
                (ApiException e) => e.validationErrors['message']?.first,
                'message error',
                'The message must not be greater than 500 characters.',
              ),
        ),
      );
    });

    test('surfaces a 409 as a conflict, not a validation error', () async {
      service = build(
        (_) async => inquiryConflictResponse(
          message: 'This listing is not open to inquiries.',
        ),
      );

      await expectLater(
        service.create(listingId: 12, message: 'Hello', purchaseInterest: true),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.kind, 'kind', ApiErrorKind.conflict)
              .having(
                (ApiException e) => e.message,
                'message',
                'This listing is not open to inquiries.',
              ),
        ),
      );
    });

    test('surfaces a 404 for a listing that no longer exists', () async {
      service = build((_) async => inquiryNotFoundResponse());

      await expectLater(
        service.create(listingId: 99, message: 'Hello', purchaseInterest: true),
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
}
