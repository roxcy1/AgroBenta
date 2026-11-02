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
      await service.create(listingId: 12, message: 'Still available?',
          collectionDateOption: InquiryCollectionDateOption.specificDate);

      expect(recorded, hasLength(1));
      expect(recorded.single.method, 'POST');
      expect(recorded.single.apiPath, InquiryEndpoints.create);
      expect(recorded.single.authorization, 'Bearer 1|mobile-token');
    });

    test('sends exactly the writable fields when all are supplied', () async {
      await service.create(
        listingId: 12,
        message: 'Is this one still available?',
        collectionDateOption: InquiryCollectionDateOption.specificDate,
        subject: 'General Inquiry',
        purchaseInterest: true,
        transactionMethod: InquiryTransactionMethod.directDeal,
        deliveryMethod: InquiryDeliveryMethod.arrangeDelivery,
        deliveryFee: '1500.00',
        contactMethod: InquiryContactMethod.inAppMessage,
        preferredSchedule: DateTime(2026, 10, 25),
        paymentMethod: InquiryPaymentMethod.gcash,
        collectionMethod: InquiryCollectionMethod.buyerArrangedTransportation,
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
      expect(recorded.single.body['payment_method'], 'gcash');
      expect(
        recorded.single.body['collection_method'],
        'buyer_arranged_transportation',
      );
    });

    test('omits preferences that were never filled in', () async {
      await service.create(
        listingId: 12,
        message: 'Just a question.',
        collectionDateOption: InquiryCollectionDateOption.specificDate,
        purchaseInterest: false,
      );

      // `purchase_interest` is answered by the form every time, so it is sent
      // even when false — false and absent are different statements. The rest
      // were never chosen and must not be invented as empty strings.
      expect(recorded.single.body, <String, dynamic>{
        'listing_id': 12,
        'message': 'Just a question.',
        'collection_date_option': 'specific_date',
        'purchase_interest': false,
      });
    });

    test('omits blank optionals rather than sending empty strings', () async {
      await service.create(
        listingId: 12,
        message: 'Just a question.',
        collectionDateOption: InquiryCollectionDateOption.specificDate,
        subject: '   ',
        purchaseInterest: true,
        deliveryFee: '',
      );

      expect(recorded.single.body.containsKey('subject'), isFalse);
      expect(recorded.single.body.containsKey('delivery_fee'), isFalse);
      expect(recorded.single.body.keys.toSet(), <String>{
        'listing_id',
        'message',
        'collection_date_option',
        'purchase_interest',
      });
    });

    test('trims the message and the delivery fee before sending', () async {
      await service.create(
        listingId: 12,
        message: '  Is this one still available?  ',
        collectionDateOption: InquiryCollectionDateOption.specificDate,
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
        collectionDateOption: InquiryCollectionDateOption.specificDate,
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
        collectionDateOption: InquiryCollectionDateOption.specificDate,
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
            'message': <String>[
              'The message must not be greater than 500 characters.',
            ],
          },
        ),
      );

        await expectLater(
          service.create(
            listingId: 12,
            message: 'x' * 501,
            collectionDateOption: InquiryCollectionDateOption.specificDate,
            purchaseInterest: true,
          ),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException e) => e.kind,
                'kind',
                ApiErrorKind.validation,
              )
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
        service.create(listingId: 12, message: 'Hello', purchaseInterest: true,
            collectionDateOption: InquiryCollectionDateOption.specificDate),
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
        service.create(listingId: 99, message: 'Hello', purchaseInterest: true,
            collectionDateOption: InquiryCollectionDateOption.specificDate),
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

  group('findExistingForListing()', () {
    test(
      'gets the buyer pre-check with no query and the bearer token',
      () async {
        service = build((_) async => inquiryCheckResponse());

        await service.findExistingForListing(12);

        expect(recorded, hasLength(1));
        expect(recorded.single.method, 'GET');
        expect(
          recorded.single.apiPath,
          InquiryEndpoints.existingForListing(12),
        );
        expect(recorded.single.apiPath, '/inquiries/listing/12');
        expect(recorded.single.authorization, 'Bearer 1|mobile-token');
        expect(
          recorded.single.query,
          isEmpty,
          reason: 'the buyer is the token, so no buyer id may be sent',
        );
        expect(recorded.single.request.body, isEmpty);
      },
    );

    test('parses the inquiry the buyer already sent', () async {
      service = build(
        (_) async => inquiryCheckResponse(
          inquiry: inquiryJson(id: 21, message: 'Already asked.'),
        ),
      );

      final Inquiry? existing = await service.findExistingForListing(12);

      expect(existing, isNotNull);
      expect(existing!.id, 21);
      expect(existing.message, 'Already asked.');
      expect(existing.listing?.id, 12);
      expect(existing.paymentMethod, InquiryPaymentMethod.cash);
      expect(existing.collectionMethod, InquiryCollectionMethod.farmPickup);
    });

    test('returns null when the buyer has sent none', () async {
      service = build((_) async => inquiryCheckResponse());

      expect(await service.findExistingForListing(12), isNull);
    });

    test('surfaces a 404 for a listing that no longer exists', () async {
      service = build((_) async => inquiryNotFoundResponse());

      await expectLater(
        service.findExistingForListing(99),
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

  group('listReceived()', () {
    test('gets the seller inbox with only page and per_page', () async {
      service = build((_) async => sellerInquiryListResponse());

      await service.listReceived(page: 2, perPage: 25);

      expect(recorded, hasLength(1));
      expect(recorded.single.method, 'GET');
      expect(recorded.single.apiPath, SellerInquiryEndpoints.received);
      expect(recorded.single.authorization, 'Bearer 1|mobile-token');
      expect(recorded.single.query, <String, String>{
        'page': '2',
        'per_page': '25',
      });
    });

    test('sends the defaults when no page is asked for', () async {
      service = build((_) async => sellerInquiryListResponse());

      await service.listReceived();

      expect(recorded.single.query, <String, String>{
        'page': '1',
        'per_page': '15',
      });
    });

    test('has no path for seller, buyer or status filters', () async {
      service = build((_) async => sellerInquiryListResponse());

      await service.listReceived();

      for (final String forbidden in <String>[
        'buyer_id',
        'seller_id',
        'status',
      ]) {
        expect(
          recorded.single.query.containsKey(forbidden),
          isFalse,
          reason: '$forbidden is server-owned or unsupported in this phase',
        );
      }
    });

    test('parses the seller resource and pagination', () async {
      service = build(
        (_) async => sellerInquiryListResponse(
          inquiries: <Map<String, dynamic>>[
            sellerInquiryJson(id: 9, buyer: inquiryBuyerJson(name: 'Ben Cruz')),
          ],
          currentPage: 1,
          lastPage: 2,
          total: 16,
        ),
      );

      final page = await service.listReceived();

      expect(page.inquiries.single.id, 9);
      expect(page.inquiries.single.buyer!.name, 'Ben Cruz');
      expect(page.inquiries.single.deliveryFee, '1500.00');
      expect(page.pagination.total, 16);
      expect(page.hasMore, isTrue);
    });
  });
}
