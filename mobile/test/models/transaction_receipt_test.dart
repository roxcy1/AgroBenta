import 'package:agrobenta_mobile/models/transaction_receipt.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/transaction_fakes.dart';

void main() {
  group('TransactionReceipt.fromJson', () {
    test('parses the exact receipt resource shape', () {
      final TransactionReceipt receipt = TransactionReceipt.fromJson(
        transactionReceiptJson(
          reference: 'TRX-012',
          buyerName: 'Pedro Reyes',
          sellerName: 'Juan Dela Cruz',
          livestockType: 'goat',
          breed: 'Boer',
          quantity: 3,
          totalAmount: '36000.50',
          paymentMethod: 'maya',
          collectionMethod: 'seller_arranged_delivery',
        ),
      );

      expect(receipt.version, 1);
      expect(receipt.reference, 'TRX-012');
      expect(receipt.buyerName, 'Pedro Reyes');
      expect(receipt.sellerName, 'Juan Dela Cruz');
      expect(receipt.livestockType, 'goat');
      expect(receipt.breed, 'Boer');
      expect(receipt.quantity, 3);
      expect(receipt.totalAmount, '36000.50');
      expect(receipt.paymentMethod, 'maya');
      expect(receipt.collectionMethod, 'seller_arranged_delivery');
      expect(receipt.status, 'completed');
      expect(receipt.completedAt, isNotNull);
      expect(receipt.completedAt!.year, 2026);
    });

    test('uses the breed as the title, or the species when there is none', () {
      final TransactionReceipt withBreed = TransactionReceipt.fromJson(
        transactionReceiptJson(breed: 'Brahman'),
      );
      final TransactionReceipt withoutBreed = TransactionReceipt.fromJson(
        transactionReceiptJson(breed: '   '),
      );

      expect(withBreed.livestockTitle, 'Brahman');
      expect(withoutBreed.livestockTitle, 'cattle');
    });

    test('maps every real fulfillment method and the legacy/null cases', () {
      const Map<String?, String> expected = <String?, String>{
        'farm_pickup': 'Personal Pickup',
        'buyer_arranged_transportation': 'Buyer-Arranged Transportation',
        'seller_arranged_delivery': 'Seller-Arranged Delivery',
        'not_sure_yet': 'Not Sure Yet',
        'discuss_with_seller': 'Discuss with seller',
        null: 'Not specified',
        'unknown_future_value': 'Not specified',
      };

      for (final MapEntry<String?, String> entry in expected.entries) {
        final TransactionReceipt receipt = TransactionReceipt.fromJson(
          transactionReceiptJson(collectionMethod: entry.key),
        );
        expect(receipt.collectionMethodLabel, entry.value);
      }
    });

    test('labels a payment preference and never invents one', () {
      const Map<String?, String> expected = <String?, String>{
        'cash': 'Cash',
        'gcash': 'GCash',
        'maya': 'Maya',
        'other': 'Other / Discuss with seller',
        null: 'Not recorded',
      };

      for (final MapEntry<String?, String> entry in expected.entries) {
        final TransactionReceipt receipt = TransactionReceipt.fromJson(
          transactionReceiptJson(paymentMethod: entry.key),
        );
        expect(receipt.paymentMethodLabel, entry.value);
      }
    });

    test('tolerates a missing completion timestamp', () {
      final TransactionReceipt receipt = TransactionReceipt.fromJson(
        transactionReceiptJson(completedAt: null),
      );

      expect(receipt.completedAt, isNull);
    });

    test('rejects a malformed nested party instead of guessing', () {
      expect(
        () => TransactionReceipt.fromJson(<String, dynamic>{
          'version': 1,
          'reference': 'TRX-001',
          'completed_at': '2026-11-10T08:15:00.000000Z',
          'buyer': <String, dynamic>{},
          'seller': <String, dynamic>{'name': 'Seller'},
          'listing': <String, dynamic>{
            'livestock_type': 'cattle',
            'breed': 'Angus',
          },
          'quantity': 1,
          'total_amount': '100.00',
          'payment_method': null,
          'collection_method': null,
          'status': 'completed',
        }),
        throwsFormatException,
      );
    });
  });
}
