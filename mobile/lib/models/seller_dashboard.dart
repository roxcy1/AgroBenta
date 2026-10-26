import '../core/utils/json_utils.dart';

/// Listing counts, by lifecycle status, for one seller.
class SellerListingSummary {
  const SellerListingSummary({
    required this.total,
    required this.draft,
    required this.pending,
    required this.active,
    required this.sold,
    required this.inactive,
  });

  factory SellerListingSummary.fromJson(Map<String, dynamic> json) {
    return SellerListingSummary(
      total: readInt(json, 'total'),
      draft: readInt(json, 'draft'),
      pending: readInt(json, 'pending'),
      active: readInt(json, 'active'),
      sold: readInt(json, 'sold'),
      inactive: readInt(json, 'inactive'),
    );
  }

  final int total;
  final int draft;
  final int pending;
  final int active;
  final int sold;
  final int inactive;
}

/// The number of inquiries received by one seller.
class SellerInquirySummary {
  const SellerInquirySummary({required this.total});

  factory SellerInquirySummary.fromJson(Map<String, dynamic> json) {
    return SellerInquirySummary(total: readInt(json, 'total'));
  }

  final int total;
}

/// Seller-side transaction counts.
///
/// The API deliberately exposes no completed, cancelled, revenue, or
/// conversion figure. This model therefore cannot display one.
class SellerTransactionSummary {
  const SellerTransactionSummary({required this.total, required this.pending});

  factory SellerTransactionSummary.fromJson(Map<String, dynamic> json) {
    return SellerTransactionSummary(
      total: readInt(json, 'total'),
      pending: readInt(json, 'pending'),
    );
  }

  final int total;
  final int pending;
}

/// The `data` payload of `GET /api/seller/dashboard`.
///
/// The seller scope is applied server-side from the token, so this object has
/// no seller id and no way to point at another account.
class SellerDashboard {
  const SellerDashboard({
    required this.listings,
    required this.inquiries,
    required this.transactions,
  });

  factory SellerDashboard.fromJson(Map<String, dynamic> json) {
    return SellerDashboard(
      listings: SellerListingSummary.fromJson(readObject(json, 'listings')),
      inquiries: SellerInquirySummary.fromJson(readObject(json, 'inquiries')),
      transactions: SellerTransactionSummary.fromJson(
        readObject(json, 'transactions'),
      ),
    );
  }

  final SellerListingSummary listings;
  final SellerInquirySummary inquiries;
  final SellerTransactionSummary transactions;

  /// Whether the seller has any listing, inquiry, or sale record.
  bool get hasActivity =>
      listings.total > 0 || inquiries.total > 0 || transactions.total > 0;

  @override
  String toString() =>
      'SellerDashboard(${listings.total} listings, '
      '${inquiries.total} inquiries, ${transactions.total} transactions)';
}
