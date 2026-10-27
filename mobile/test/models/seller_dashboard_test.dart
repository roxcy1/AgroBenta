import 'package:agrobenta_mobile/models/seller_dashboard.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seller_dashboard_fakes.dart';

void main() {
  group('SellerDashboard.fromJson', () {
    test('reads the exact server shape', () {
      final SellerDashboard dashboard = SellerDashboard.fromJson(
        sellerDashboardJson(
          totalListings: 6,
          draft: 1,
          pendingListings: 1,
          active: 2,
          sold: 1,
          inactive: 1,
          totalInquiries: 3,
          totalTransactions: 4,
          pendingTransactions: 2,
        ),
      );

      expect(dashboard.listings.total, 6);
      expect(dashboard.listings.draft, 1);
      expect(dashboard.listings.pending, 1);
      expect(dashboard.listings.active, 2);
      expect(dashboard.listings.sold, 1);
      expect(dashboard.listings.inactive, 1);
      expect(dashboard.inquiries.total, 3);
      expect(dashboard.transactions.total, 4);
      expect(dashboard.transactions.pending, 2);
      expect(dashboard.hasActivity, isTrue);
    });

    test('an all-zero dashboard has no activity', () {
      final SellerDashboard dashboard = SellerDashboard.fromJson(
        sellerDashboardJson(
          totalListings: 0,
          draft: 0,
          pendingListings: 0,
          active: 0,
          sold: 0,
          inactive: 0,
          totalInquiries: 0,
          totalTransactions: 0,
          pendingTransactions: 0,
        ),
      );

      expect(dashboard.hasActivity, isFalse);
    });

    test('throws a named format error when a section is missing', () {
      expect(
        () => SellerDashboard.fromJson(<String, dynamic>{
          'listings': sellerDashboardJson()['listings'],
          'inquiries': <String, dynamic>{'total': 0},
        }),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            contains('transactions'),
          ),
        ),
      );
    });
  });
}
