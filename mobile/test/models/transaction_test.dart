import 'package:agrobenta_mobile/models/transaction.dart';
import 'package:agrobenta_mobile/models/transaction_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/transaction_fakes.dart';

void main() {
  group('Transaction.fromJson', () {
    test('parses the MobileTransactionResource contract exactly', () {
      final Transaction transaction = Transaction.fromJson(
        transactionJson(
          id: 42,
          role: 'seller',
          quantity: 3,
          totalAmount: '127500.00',
          status: 'completed',
          listing: transactionListingJson(
            id: 9,
            livestockType: 'Goat',
            breed: 'Boer',
            photos: <Object?>['https://cdn.example.test/goats.jpg'],
          ),
          counterparty: transactionCounterpartyJson(
            id: 7,
            name: 'Ana Reyes',
            email: 'ana@example.test',
          ),
        ),
      );

      expect(transaction.id, 42);
      expect(transaction.role, TransactionRole.seller);
      expect(transaction.quantity, 3);
      expect(
        transaction.totalAmount,
        '127500.00',
        reason: 'the server decimal arrives as a string and stays verbatim',
      );
      expect(transaction.status, TransactionStatus.completed);
      expect(transaction.listing.id, 9);
      expect(transaction.listing.title, 'Boer');
      expect(
        transaction.listing.loadablePhotoUrl,
        'https://cdn.example.test/goats.jpg',
      );
      expect(transaction.counterparty.id, 7);
      expect(transaction.counterparty.name, 'Ana Reyes');
      expect(transaction.counterparty.email, 'ana@example.test');
      expect(transaction.createdAt, isNotNull);
      expect(transaction.updatedAt, isNotNull);
    });

    test('the amount is never a number the client could compute with', () {
      final Transaction transaction = Transaction.fromJson(
        transactionJson(quantity: 4, totalAmount: '170000.00'),
      );

      expect(transaction.totalAmount, isA<String>());
      expect(transaction.totalAmount, '170000.00');
    });

    test('displayId is the padded TRX form and the id stays an int', () {
      final Transaction transaction = Transaction.fromJson(
        transactionJson(id: 7),
      );

      expect(transaction.displayId, 'TRX-007');
      expect(transaction.id, 7);
    });

    test('isPending is true only for the pending state', () {
      Transaction parse(String status) =>
          Transaction.fromJson(transactionJson(status: status));

      expect(parse('pending').isPending, isTrue);
      expect(parse('completed').isPending, isFalse);
      expect(parse('cancelled').isPending, isFalse);
    });

    test('an unknown status fails loudly instead of defaulting', () {
      expect(
        () => Transaction.fromJson(transactionJson(status: 'refunded')),
        throwsFormatException,
      );
    });

    test('an unknown role fails loudly instead of defaulting', () {
      expect(
        () => Transaction.fromJson(transactionJson(role: 'admin')),
        throwsFormatException,
      );
    });

    test('parses fulfillment status, permitted actions and terms', () {
      final Transaction transaction = Transaction.fromJson(
        transactionJson(
          status: 'pending',
          fulfillmentStatus: 'ready_for_pickup',
          permittedActions: <String>['picked_up', 'cancel'],
          collectionMethod: 'seller_arranged_delivery',
          pickupDate: '2026-11-20',
          paymentMethod: 'gcash',
        ),
      );

      expect(
        transaction.fulfillmentStatus,
        TransactionFulfillmentStatus.readyForPickup,
      );
      expect(transaction.permittedActions, <String>['picked_up', 'cancel']);
      expect(transaction.terms.collectionMethod, 'seller_arranged_delivery');
      expect(
        transaction.terms.collectionMethodLabel,
        'Seller-Arranged Delivery',
      );
      expect(transaction.terms.isDelivery, isTrue);
      expect(transaction.terms.paymentMethod, 'gcash');
      expect(transaction.terms.pickupDate, isNotNull);
      expect(transaction.canCancel, isTrue);
      expect(transaction.canConfirmReceived, isFalse);
    });

    test('accepts a legacy null fulfillment stage without crashing', () {
      final Transaction transaction = Transaction.fromJson(
        transactionJson(
          status: 'pending',
          fulfillmentStatus: null,
          permittedActions: const <String>['cancel'],
        ),
      );

      expect(transaction.fulfillmentStatus, isNull);
      expect(transaction.hasLegacyFulfillment, isTrue);
      expect(
        transaction.effectiveFulfillmentStatus,
        TransactionFulfillmentStatus.confirmed,
      );
    });

    test(
      'keeps an unknown non-null fulfillment stage distinct from legacy',
      () {
        final Transaction transaction = Transaction.fromJson(
          transactionJson(
            status: 'pending',
            fulfillmentStatus: 'future_stage',
            permittedActions: const <String>['preparing'],
          ),
        );

        expect(transaction.fulfillmentStatus, isNull);
        expect(transaction.fulfillmentStatusValue, 'future_stage');
        expect(transaction.hasUnknownFulfillmentStatus, isTrue);
        expect(transaction.hasLegacyFulfillment, isFalse);
        expect(transaction.effectiveFulfillmentStatus, isNull);
      },
    );

    test('derives the one next seller action from the server allow-list', () {
      final Transaction transaction = Transaction.fromJson(
        transactionJson(
          role: 'seller',
          permittedActions: <String>['delivered', 'cancel'],
        ),
      );

      expect(
        transaction.nextSellerAction,
        TransactionFulfillmentAction.delivered,
      );
    });

    test('does not treat an unknown permitted action as a button', () {
      final Transaction transaction = Transaction.fromJson(
        transactionJson(
          permittedActions: const <String>['teleport', 'confirm_received'],
        ),
      );

      expect(transaction.permittedActions, contains('teleport'));
      expect(transaction.nextSellerAction, isNull);
      expect(transaction.canConfirmReceived, isTrue);
    });
  });

  group('TransactionListing', () {
    test('falls back to the species when there is no breed', () {
      final Transaction transaction = Transaction.fromJson(
        transactionJson(
          listing: transactionListingJson(breed: '', livestockType: 'Cattle'),
        ),
      );

      expect(transaction.listing.title, 'Cattle');
    });

    test('skips photos the client cannot fetch directly', () {
      final Transaction transaction = Transaction.fromJson(
        transactionJson(
          listing: transactionListingJson(
            photos: <Object?>['relative-path.jpg'],
          ),
        ),
      );

      expect(transaction.listing.loadablePhotoUrl, isNull);
    });
  });

  group('TransactionPage.fromJson', () {
    test('parses the hand-rolled transactions + pagination envelope', () {
      final TransactionPage page = TransactionPage.fromJson(
        transactionPageJson(
          transactions: <Map<String, dynamic>>[
            transactionJson(id: 3),
            transactionJson(id: 2),
          ],
          currentPage: 1,
          lastPage: 3,
          perPage: 15,
          total: 31,
        ),
      );

      expect(page.transactions, hasLength(2));
      expect(page.transactions.first.id, 3);
      expect(page.pagination.currentPage, 1);
      expect(page.pagination.lastPage, 3);
      expect(page.hasMore, isTrue);
      expect(page.isEmpty, isFalse);
    });

    test('a last page reports no more and an empty page reports empty', () {
      final TransactionPage last = TransactionPage.fromJson(
        transactionPageJson(
          transactions: <Map<String, dynamic>>[transactionJson()],
          currentPage: 3,
          lastPage: 3,
          total: 31,
        ),
      );
      final TransactionPage empty = TransactionPage.fromJson(
        transactionPageJson(transactions: <Map<String, dynamic>>[], total: 0),
      );

      expect(last.hasMore, isFalse);
      expect(empty.isEmpty, isTrue);
      expect(empty.transactions, isEmpty);
    });

    test('an unexpected array key is an empty page, not a crash', () {
      // The envelope key is endpoint-specific ('transactions' here). A
      // foreign key must not be generalised into a guessed shape; it simply
      // yields no rows, which the caller renders as an honest empty state.
      final TransactionPage page = TransactionPage.fromJson(<String, dynamic>{
        'items': <dynamic>[],
        'pagination': <String, dynamic>{
          'current_page': 1,
          'last_page': 1,
          'per_page': 15,
          'total': 0,
        },
      });

      expect(page.transactions, isEmpty);
      expect(page.isEmpty, isTrue);
    });
  });
}
