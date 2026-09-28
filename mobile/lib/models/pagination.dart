/// Pagination shape returned by the AgroBenta API.
///
/// The backend does **not** return Laravel's default `LengthAwarePaginator`
/// structure. Each controller hand-rolls a nested `pagination` object inside
/// `data`:
///
/// ```json
/// {
///   "success": true,
///   "data": {
///     "listings": [ ],
///     "pagination": { "current_page": 1, "last_page": 5, "per_page": 15, "total": 68 }
///   }
/// }
/// ```
///
/// Note that the array key is endpoint-specific (`listings`, `users`,
/// `transactions`, `verifications`, `activities`) rather than a uniform `data`.
/// Do not try to generalise the array key — parse it per endpoint.
///
/// Verified against:
///   * `backend/app/Http/Controllers/Api/Admin/ListingController.php`
///   * `backend/app/Http/Controllers/Api/Admin/UserController.php`
library;

import '../core/utils/json_utils.dart';

class Pagination {
  const Pagination({
    required this.currentPage,
    required this.lastPage,
    required this.perPage,
    required this.total,
  });

  factory Pagination.fromJson(Map<String, dynamic> json) {
    return Pagination(
      currentPage: readInt(json, 'current_page'),
      lastPage: readInt(json, 'last_page'),
      perPage: readInt(json, 'per_page'),
      total: readInt(json, 'total'),
    );
  }

  /// 1-based index of the page currently being returned.
  final int currentPage;

  /// Total number of pages. Equals `1` when [total] is zero.
  final int lastPage;

  final int perPage;

  /// Total number of records across all pages.
  final int total;

  bool get hasPreviousPage => currentPage > 1;

  bool get hasNextPage => currentPage < lastPage;

  /// Zero-based index for passing straight through to a Laravel `page` query
  /// parameter. Laravel pages are 1-based, so the subtraction here is
  /// deliberate — do not remove it.
  int get laravelPageIndex => currentPage - 1;
}
