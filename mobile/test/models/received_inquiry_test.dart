import 'package:agrobenta_mobile/models/inquiry.dart';
import 'package:agrobenta_mobile/models/received_inquiry.dart';
import 'package:agrobenta_mobile/models/received_inquiry_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/inquiry_fakes.dart';

void main() {
  group('ReceivedInquiry.fromJson', () {
    test('parses the SellerInquiryResource contract exactly', () {
      final ReceivedInquiry inquiry = ReceivedInquiry.fromJson(
        sellerInquiryJson(
          id: 42,
          buyer: inquiryBuyerJson(id: 9, name: 'Maria Santos'),
          listing: inquiryListingJson(
            id: 12,
            livestockType: 'Goat',
            breed: 'Boer',
          ),
          subject: 'General Inquiry',
          message: 'Is this one still available?',
          purchaseInterest: false,
          transactionMethod: 'arrange_delivery',
          deliveryMethod: 'buyer_pickup',
          deliveryFee: '1500.00',
          contactMethod: 'in_app_message',
          preferredSchedule: '2026-10-25',
          createdAt: '2026-10-19T08:15:00.000000Z',
        ),
      );

      expect(inquiry.id, 42);
      expect(inquiry.buyer!.id, 9);
      expect(inquiry.buyer!.name, 'Maria Santos');
      expect(inquiry.listing!.id, 12);
      expect(inquiry.listing!.title, 'Boer');
      expect(inquiry.subject, 'General Inquiry');
      expect(inquiry.message, 'Is this one still available?');
      expect(inquiry.purchaseInterest, isFalse);
      expect(
        inquiry.transactionMethod,
        InquiryTransactionMethod.arrangeDelivery,
      );
      expect(inquiry.deliveryMethod, InquiryDeliveryMethod.buyerPickup);
      expect(inquiry.contactMethod, InquiryContactMethod.inAppMessage);
      expect(inquiry.deliveryFee, '1500.00');
      expect(inquiry.preferredSchedule, DateTime(2026, 10, 25));
      expect(inquiry.createdAt, isNotNull);
    });

    test(
      'a deleted listing and a missing buyer do not invalidate the inquiry',
      () {
        final Map<String, dynamic> json = sellerInquiryJson();
        json['buyer'] = null;
        json['listing'] = null;

        final ReceivedInquiry inquiry = ReceivedInquiry.fromJson(json);

        expect(inquiry.buyer, isNull);
        expect(inquiry.listing, isNull);
        expect(inquiry.message, isNotEmpty);
      },
    );

    test('every preference may be absent, null not defaulted', () {
      final Map<String, dynamic> json = sellerInquiryJson();
      json['subject'] = null;
      json['purchase_interest'] = null;
      json['transaction_method'] = null;
      json['delivery_method'] = null;
      json['delivery_fee'] = null;
      json['contact_method'] = null;
      json['preferred_schedule'] = null;
      json['created_at'] = null;

      final ReceivedInquiry inquiry = ReceivedInquiry.fromJson(json);

      expect(inquiry.subject, isNull);
      expect(inquiry.purchaseInterest, isNull);
      expect(inquiry.transactionMethod, isNull);
      expect(inquiry.deliveryMethod, isNull);
      expect(inquiry.deliveryFee, isNull);
      expect(inquiry.contactMethod, isNull);
      expect(inquiry.preferredSchedule, isNull);
      expect(inquiry.createdAt, isNull);
    });

    test('the seller resource never carries a status', () {
      final Map<String, dynamic> json = sellerInquiryJson();
      expect(json.containsKey('status'), isFalse);
    });

    test('a decimal arrives from SQLite as a number and still parses', () {
      final ReceivedInquiry inquiry = ReceivedInquiry.fromJson(
        sellerInquiryJson(deliveryFee: 1500.0),
      );

      expect(inquiry.deliveryFee, isA<String>());
      expect(inquiry.deliveryFee, '1500.0');
    });
  });

  group('ReceivedInquiryPage.fromJson', () {
    test('parses the inquiries array and pagination', () {
      final ReceivedInquiryPage page = ReceivedInquiryPage.fromJson(
        <String, dynamic>{
          'inquiries': <Map<String, dynamic>>[
            sellerInquiryJson(id: 5),
            sellerInquiryJson(id: 4),
          ],
          'pagination': <String, dynamic>{
            'current_page': 2,
            'last_page': 4,
            'per_page': 15,
            'total': 50,
          },
        },
      );

      expect(page.inquiries.map((ReceivedInquiry i) => i.id), <int>[5, 4]);
      expect(page.pagination.currentPage, 2);
      expect(page.pagination.lastPage, 4);
      expect(page.hasMore, isTrue);
      expect(page.isEmpty, isFalse);
    });

    test('an empty page is empty but still has pagination', () {
      final ReceivedInquiryPage page = ReceivedInquiryPage.fromJson(
        <String, dynamic>{
          'inquiries': <Map<String, dynamic>>[],
          'pagination': <String, dynamic>{
            'current_page': 1,
            'last_page': 1,
            'per_page': 15,
            'total': 0,
          },
        },
      );

      expect(page.isEmpty, isTrue);
      expect(page.hasMore, isFalse);
    });
  });
}
