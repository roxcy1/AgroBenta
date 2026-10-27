import '../core/utils/json_utils.dart';
import 'pagination.dart';
import 'received_inquiry.dart';

/// One page of the seller's received inquiries plus their pagination.
///
/// Mirrors the `data` payload of `GET /api/seller/inquiries`, which uses the
/// hand-rolled paginated envelope from the API contract with the
/// endpoint-specific array key `inquiries`:
///
/// ```json
/// {
///   "success": true,
///   "data": {
///     "inquiries": [ /* SellerInquiryResource[] */ ],
///     "pagination": { "current_page": 1, "last_page": 5, "per_page": 15, "total": 68 }
///   }
/// }
/// ```
class ReceivedInquiryPage {
  const ReceivedInquiryPage({
    required this.inquiries,
    required this.pagination,
  });

  factory ReceivedInquiryPage.fromJson(Map<String, dynamic> json) {
    return ReceivedInquiryPage(
      inquiries: readObjectList(
        json,
        'inquiries',
      ).map(ReceivedInquiry.fromJson).toList(growable: false),
      pagination: Pagination.fromJson(readObject(json, 'pagination')),
    );
  }

  /// The inquiries on this page, newest first.
  ///
  /// Order is the server's: `created_at DESC, id DESC`. The app does not
  /// re-sort, because doing so would disagree with the pagination the server
  /// computed over that same ordering.
  final List<ReceivedInquiry> inquiries;

  final Pagination pagination;

  bool get hasMore => pagination.hasNextPage;

  bool get isEmpty => inquiries.isEmpty;

  @override
  String toString() =>
      'ReceivedInquiryPage(${inquiries.length} inquiries, '
      'page ${pagination.currentPage}/${pagination.lastPage})';
}
