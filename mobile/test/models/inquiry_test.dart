import 'package:agrobenta_mobile/models/inquiry.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/inquiry_fakes.dart';

void main() {
  group('Inquiry.fromJson', () {
    test('parses the MobileInquiryResource contract exactly', () {
      final Inquiry inquiry = Inquiry.fromJson(
        inquiryJson(
          id: 42,
          listing: inquiryListingJson(id: 9, livestockType: 'Goat', breed: 'Boer'),
          subject: 'General Inquiry',
          message: 'Is this one still available?',
          purchaseInterest: false,
          transactionMethod: 'arrange_delivery',
          deliveryMethod: 'arrange_delivery',
          deliveryFee: '1500.00',
          contactMethod: 'in_app_message',
          paymentMethod: 'cash',
          collectionMethod: 'farm_pickup',
          preferredSchedule: '2026-10-25',
          createdAt: '2026-10-19T08:15:00.000000Z',
        ),
      );

      expect(inquiry.id, 42);
      expect(inquiry.listing!.id, 9);
      expect(inquiry.listing!.title, 'Boer');
      expect(inquiry.subject, 'General Inquiry');
      expect(inquiry.message, 'Is this one still available?');
      expect(inquiry.purchaseInterest, isFalse);
      expect(inquiry.transactionMethod, InquiryTransactionMethod.arrangeDelivery);
      expect(inquiry.deliveryMethod, InquiryDeliveryMethod.arrangeDelivery);
      expect(inquiry.contactMethod, InquiryContactMethod.inAppMessage);
      expect(inquiry.paymentMethod, InquiryPaymentMethod.cash);
      expect(inquiry.collectionMethod, InquiryCollectionMethod.farmPickup);
      expect(inquiry.preferredSchedule, DateTime(2026, 10, 25));
      expect(inquiry.createdAt, isNotNull);
    });

    test('the delivery fee is a string the client never computes with', () {
      final Inquiry inquiry = Inquiry.fromJson(
        inquiryJson(deliveryFee: '1500.00'),
      );

      expect(inquiry.deliveryFee, isA<String>());
      expect(inquiry.deliveryFee, '1500.00');
    });

    test('a decimal arrives from SQLite as a number and still parses', () {
      // The same MySQL/SQLite divergence the listing fixture reproduces:
      // MySQL's PDO returns "1500.00", SQLite returns the number 1500.0. The
      // number is stringified verbatim — the point is that it stays a String
      // the display layer formats, never a double the client could compute
      // with; the exact digits are whatever the transport carried.
      final Inquiry inquiry = Inquiry.fromJson(
        inquiryJson(deliveryFee: 1500.0),
      );

      expect(inquiry.deliveryFee, isA<String>());
      expect(inquiry.deliveryFee, '1500.0');
    });

    test('every preference may be absent — null, not defaulted', () {
      final Inquiry inquiry = Inquiry.fromJson(<String, dynamic>{
        'id': 1,
        'listing': null,
        'subject': null,
        'message': 'Plain message.',
        'purchase_interest': null,
        'transaction_method': null,
        'delivery_method': null,
        'delivery_fee': null,
        'contact_method': null,
        'preferred_schedule': null,
        'payment_method': null,
        'collection_method': null,
        'created_at': null,
      });

      expect(inquiry.listing, isNull);
      expect(inquiry.subject, isNull);
      expect(inquiry.purchaseInterest, isNull);
      expect(inquiry.transactionMethod, isNull);
      expect(inquiry.deliveryMethod, isNull);
      expect(inquiry.deliveryFee, isNull);
      expect(inquiry.contactMethod, isNull);
      expect(inquiry.preferredSchedule, isNull);
      expect(inquiry.paymentMethod, isNull);
      expect(inquiry.collectionMethod, isNull);
      expect(inquiry.createdAt, isNull);
    });

    test('a null listing snapshot keeps the inquiry valid', () {
      final Map<String, dynamic> json = inquiryJson();
      json['listing'] = null;

      final Inquiry inquiry = Inquiry.fromJson(json);

      expect(inquiry.listing, isNull);
      expect(inquiry.message, isNotEmpty);
    });

    test('an unknown transaction method fails loudly', () {
      expect(
        () => Inquiry.fromJson(inquiryJson(transactionMethod: 'cod')),
        throwsFormatException,
      );
    });

    test('an unknown delivery method fails loudly', () {
      expect(
        () => Inquiry.fromJson(inquiryJson(deliveryMethod: 'drone')),
        throwsFormatException,
      );
    });

    test('an unknown contact method fails loudly', () {
      expect(
        () => Inquiry.fromJson(inquiryJson(contactMethod: 'phone')),
        throwsFormatException,
      );
    });

    test('an unknown payment method fails loudly', () {
      expect(
        () => Inquiry.fromJson(inquiryJson(paymentMethod: 'crypto')),
        throwsFormatException,
      );
    });

    test('an unknown collection method fails loudly', () {
      expect(
        () => Inquiry.fromJson(inquiryJson(collectionMethod: 'drone')),
        throwsFormatException,
      );
    });

    test('a status key the resource never sends is ignored', () {
      // The server-side workflow marker (`open` / `responded` / `closed`) is
      // an administrator bookmark. The model has no `status` property — that
      // absence is enforced by the analyzer — and an unexpected key in the
      // payload must parse as no-ops rather than become a field.
      final Map<String, dynamic> json = inquiryJson();
      json['status'] = 'responded';

      final Inquiry inquiry = Inquiry.fromJson(json);

      expect(inquiry.id, 5);
      expect(inquiry.message, isNotEmpty);
    });
  });

  group('InquiryListing', () {
    test('falls back to the species when there is no breed', () {
      final Inquiry inquiry = Inquiry.fromJson(
        inquiryJson(
          listing: inquiryListingJson(breed: '', livestockType: 'Cattle'),
        ),
      );

      expect(inquiry.listing!.title, 'Cattle');
    });
  });

  group('enum values', () {
    test('carry exactly the strings the API stores', () {
      expect(InquiryTransactionMethod.directDeal.value, 'direct_deal');
      expect(InquiryTransactionMethod.arrangeDelivery.value, 'arrange_delivery');
      expect(InquiryDeliveryMethod.buyerPickup.value, 'buyer_pickup');
      expect(InquiryDeliveryMethod.arrangeDelivery.value, 'arrange_delivery');
      expect(InquiryContactMethod.inAppMessage.value, 'in_app_message');
      expect(InquiryPaymentMethod.cash.value, 'cash');
      expect(InquiryPaymentMethod.gcash.value, 'gcash');
      expect(InquiryPaymentMethod.maya.value, 'maya');
      expect(InquiryPaymentMethod.other.value, 'other');
      expect(InquiryCollectionMethod.farmPickup.value, 'farm_pickup');
      expect(InquiryCollectionMethod.buyerArrangedTransportation.value,
          'buyer_arranged_transportation');
      expect(InquiryCollectionMethod.discussWithSeller.value,
          'discuss_with_seller');
    });

    test('fromValue round-trips every case', () {
      for (final InquiryTransactionMethod value
          in InquiryTransactionMethod.values) {
        expect(
          InquiryTransactionMethod.fromValue(value.value),
          value,
        );
      }
      for (final InquiryDeliveryMethod value in InquiryDeliveryMethod.values) {
        expect(InquiryDeliveryMethod.fromValue(value.value), value);
      }
      for (final InquiryContactMethod value in InquiryContactMethod.values) {
        expect(InquiryContactMethod.fromValue(value.value), value);
      }
      for (final InquiryPaymentMethod value in InquiryPaymentMethod.values) {
        expect(InquiryPaymentMethod.fromValue(value.value), value);
      }
      for (final InquiryCollectionMethod value
          in InquiryCollectionMethod.values) {
        expect(InquiryCollectionMethod.fromValue(value.value), value);
      }
    });
  });
}
