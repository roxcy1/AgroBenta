import 'package:agrobenta_mobile/models/offer.dart';
import 'package:agrobenta_mobile/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/offer_fakes.dart';
import '../support/transaction_fakes.dart';

void main() {
  group('Offer.fromJson', () {
    test('parses the OfferResource contract exactly', () {
      final Offer offer = Offer.fromJson(
        offerJson(
          id: 9,
          inquiryId: 5,
          listingId: 12,
          sellerId: 3,
          buyerId: 7,
          proposedAmount: '48000.00',
          status: 'pending',
        ),
      );

      expect(offer.id, 9);
      expect(offer.inquiryId, 5);
      expect(offer.listingId, 12);
      expect(offer.sellerId, 3);
      expect(offer.buyerId, 7);
      expect(
        offer.proposedAmount,
        '48000.00',
        reason: 'money stays the decimal string the API sent',
      );
      expect(offer.status, OfferStatus.pending);
      expect(offer.respondedAt, isNull);
      expect(offer.createdAt, isNotNull);
    });

    test('maps every server status and is actionable only while pending', () {
      expect(OfferStatus.fromValue('accepted'), OfferStatus.accepted);
      expect(OfferStatus.fromValue('declined'), OfferStatus.declined);
      expect(OfferStatus.fromValue('withdrawn'), OfferStatus.withdrawn);
      expect(OfferStatus.fromValue('expired'), OfferStatus.expired);

      expect(OfferStatus.pending.isPending, isTrue);
      expect(OfferStatus.accepted.isPending, isFalse);
      expect(OfferStatus.declined.isPending, isFalse);
      expect(OfferStatus.withdrawn.isPending, isFalse);
      expect(OfferStatus.expired.isPending, isFalse);
    });

    test('an unknown status fails loudly rather than defaulting', () {
      expect(() => OfferStatus.fromValue('countered'), throwsFormatException);
    });

    test('knows which party the viewer is from the server ids', () {
      final Offer offer = Offer.fromJson(offerJson(sellerId: 3, buyerId: 7));

      expect(offer.isSeller(3), isTrue);
      expect(offer.isBuyer(3), isFalse);
      expect(offer.isBuyer(7), isTrue);
      expect(offer.isSeller(7), isFalse);
      expect(offer.isBuyer(99), isFalse);
      expect(offer.isSeller(99), isFalse);
    });
  });

  group('OfferAcceptance.fromJson', () {
    test('carries the accepted offer and the created transaction', () {
      final OfferAcceptance acceptance = OfferAcceptance.fromJson(
        <String, dynamic>{
          'offer': offerJson(id: 2, status: 'accepted'),
          'transaction': transactionJson(
            id: 41,
            totalAmount: '48000.00',
            status: 'pending',
          ),
        },
      );

      expect(acceptance.offer.id, 2);
      expect(acceptance.offer.status, OfferStatus.accepted);
      expect(acceptance.transaction.id, 41);
      expect(
        acceptance.transaction.totalAmount,
        '48000.00',
        reason: 'the acceptance response is the only transaction id source',
      );
      expect(acceptance.transaction.status, TransactionStatus.pending);
    });
  });
}
