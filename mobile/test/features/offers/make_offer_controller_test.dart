import 'package:agrobenta_mobile/features/offers/state/make_offer_controller.dart';
import 'package:agrobenta_mobile/features/offers/state/offer_state.dart';
import 'package:agrobenta_mobile/models/inquiry.dart';
import 'package:agrobenta_mobile/models/offer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/offer_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  setUp(() {
    tokenStore = FakeTokenStore('token');
    recorded = <RecordedRequest>[];
  });

  MakeOfferController build(
    Future<http.Response> Function(RecordedRequest request) handler,
  ) {
    final MakeOfferController controller = buildMakeOfferController(
      tokenStore,
      handler,
      recorded: recorded,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  group('client validation mirrors StoreOfferRequest', () {
    test('an empty amount never reaches the API', () async {
      final MakeOfferController controller = build(
        (_) async => offerCreatedResponse(),
      );

      final Offer? created = await controller.submit(
        inquiryId: 5,
        listingId: 12,
        amount: '   ',
      );

      expect(created, isNull);
      expect(controller.state.amountErrorMessage, isNotEmpty);
      expect(recorded, isEmpty);
    });

    test('a non-numeric amount never reaches the API', () async {
      final MakeOfferController controller = build(
        (_) async => offerCreatedResponse(),
      );

      await controller.submit(inquiryId: 5, listingId: 12, amount: '48,000');

      expect(controller.state.amountErrorMessage, isNotEmpty);
      expect(recorded, isEmpty);
    });

    test('an amount below 0.01 never reaches the API', () async {
      final MakeOfferController controller = build(
        (_) async => offerCreatedResponse(),
      );

      await controller.submit(inquiryId: 5, listingId: 12, amount: '0.00');

      expect(controller.state.amountErrorMessage, isNotEmpty);
      expect(recorded, isEmpty);
    });
  });

  group('submit', () {
    test('trims the amount and sends only the three request fields', () async {
      final MakeOfferController controller = build(
        (_) async => offerCreatedResponse(
          offer: offerJson(id: 8, proposedAmount: '48000.00'),
        ),
      );

      final Offer? created = await controller.submit(
        inquiryId: 5,
        listingId: 12,
        amount: ' 48000.00 ',
      );

      expect(created?.id, 8);
      expect(controller.state.status, MakeOfferStatus.succeeded);
      expect(recorded.single.method, 'POST');
      expect(recorded.single.apiPath, '/offers');
      expect(recorded.single.body.keys.toSet(), <String>{
        'inquiry_id',
        'listing_id',
        'proposed_amount',
      });
      expect(recorded.single.body['proposed_amount'], '48000.00');
    });

    test(
      'sends the proposed terms without inventing any other field',
      () async {
        final MakeOfferController controller = build(
          (_) async => offerCreatedResponse(
            offer: offerJson(id: 9, proposedAmount: '47000.00'),
          ),
        );

        await controller.submit(
          inquiryId: 5,
          listingId: 12,
          amount: '47000.00',
          pickupDate: DateTime(2036, 11, 12),
          paymentMethod: InquiryPaymentMethod.cash,
          collectionMethod: InquiryCollectionMethod.farmPickup,
          note: '  Bring a helper.  ',
        );

        final Map<String, dynamic> body = recorded.single.body;
        expect(body.keys.toSet(), <String>{
          'inquiry_id',
          'listing_id',
          'proposed_amount',
          'proposed_pickup_date',
          'payment_method',
          'collection_method',
          'note',
        });
        expect(body['proposed_pickup_date'], '2036-11-12');
        expect(body['payment_method'], 'cash');
        expect(body['collection_method'], 'farm_pickup');
        expect(body['note'], 'Bring a helper.');

        // Server-owned fields never travel from the client.
        expect(body.containsKey('buyer_id'), isFalse);
        expect(body.containsKey('seller_id'), isFalse);
        expect(body.containsKey('status'), isFalse);
      },
    );

    test('a server 422 becomes the amount field error', () async {
      final MakeOfferController controller = build(
        (_) async => offerValidationResponse(),
      );

      final Offer? created = await controller.submit(
        inquiryId: 5,
        listingId: 12,
        amount: '1.00',
      );

      expect(created, isNull);
      expect(controller.state.status, MakeOfferStatus.failed);
      expect(
        controller.state.amountErrorMessage,
        'The proposed amount must be at least 0.01.',
      );
    });
  });
}
