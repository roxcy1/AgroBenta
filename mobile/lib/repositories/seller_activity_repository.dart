import '../core/constants/api_constants.dart';
import '../models/seller_activity.dart';
import '../services/seller_activity_service.dart';

/// Orchestration for the seller activity feed.
///
/// Thin by design, like the other read repositories: page-size policy lives on
/// the endpoint constant and no error is re-worded here.
class SellerActivityRepository {
  const SellerActivityRepository(this._service);

  final SellerActivityService _service;

  /// The newest seller-relevant events, newest first (Seller Home).
  Future<List<SellerActivity>> latest({
    int limit = SellerActivityEndpoints.defaultLimit,
  }) {
    return _service.latest(limit: limit);
  }

  /// One filtered page for the All Activities screen.
  Future<SellerActivityPage> page({
    int page = 1,
    int perPage = SellerActivityEndpoints.defaultPageSize,
    String? category,
    DateTime? from,
    DateTime? to,
  }) {
    return _service.page(
      page: page,
      perPage: perPage,
      category: category,
      from: from,
      to: to,
    );
  }
}
