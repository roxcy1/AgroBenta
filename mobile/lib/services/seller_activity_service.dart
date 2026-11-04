import '../core/constants/api_constants.dart';
import '../core/network/api_client.dart';
import '../models/pagination.dart';
import '../models/seller_activity.dart';

/// The seller activity API surface.
///
/// One endpoint, two shapes: the legacy `limit` query (Seller Home's latest
/// five) and the paginated/filtered query used by All Activities. Both are
/// built from an explicit allow-list of parameters; the seller scope comes from
/// the bearer token handled by [ApiClient].
class SellerActivityService {
  const SellerActivityService(this._apiClient);

  final ApiClient _apiClient;

  /// `GET /seller/activities?limit=…` — newest first (Seller Home).
  Future<List<SellerActivity>> latest({
    int limit = SellerActivityEndpoints.defaultLimit,
  }) {
    return _apiClient.get<List<SellerActivity>>(
      SellerActivityEndpoints.list,
      query: <String, dynamic>{'limit': limit},
      parse: (Object? data) =>
          _parsePage(data, 'GET ${SellerActivityEndpoints.list}').activities,
    );
  }

  /// One page of the seller's activity feed, optionally filtered.
  Future<SellerActivityPage> page({
    int page = 1,
    int perPage = SellerActivityEndpoints.defaultPageSize,
    String? category,
    DateTime? from,
    DateTime? to,
  }) {
    final Map<String, dynamic> query = <String, dynamic>{
      'page': page,
      'per_page': perPage,
    };
    if (category != null && category.isNotEmpty) {
      query['category'] = category;
    }
    if (from != null) {
      query['from'] = _isoDate(from);
    }
    if (to != null) {
      query['to'] = _isoDate(to);
    }

    return _apiClient.get<SellerActivityPage>(
      SellerActivityEndpoints.list,
      query: query,
      parse: (Object? data) =>
          _parsePage(data, 'GET ${SellerActivityEndpoints.list}'),
    );
  }

  /// `yyyy-MM-dd` — the date-only shape the API validates.
  static String _isoDate(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-$month-$day';
  }

  static SellerActivityPage _parsePage(Object? data, String context) {
    final Map<String, dynamic> map = _asObject(data, context);
    final List<dynamic> raw =
        (map['activities'] as List<dynamic>?) ?? const <dynamic>[];
    final Map<String, dynamic>? pagination = _nullableObject(
      map['pagination'],
    );

    return SellerActivityPage(
      activities: raw
          .whereType<Map<String, dynamic>>()
          .map(SellerActivity.fromJson)
          .toList(growable: false),
      pagination: pagination == null
          ? Pagination.fromJson(<String, dynamic>{
              'current_page': 1,
              'last_page': 1,
              'per_page': raw.length,
              'total': raw.length,
            })
          : Pagination.fromJson(pagination),
    );
  }

  static Map<String, dynamic>? _nullableObject(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return null;
  }

  static Map<String, dynamic> _asObject(Object? data, String context) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return data.cast<String, dynamic>();
    }
    throw FormatException(
      'Expected the $context response data to be a JSON object, got '
      '${data.runtimeType}.',
    );
  }
}
