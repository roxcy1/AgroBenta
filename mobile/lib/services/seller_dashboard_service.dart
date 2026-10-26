import '../core/constants/api_constants.dart';
import '../core/network/api_client.dart';
import '../models/seller_dashboard.dart';

/// The seller dashboard API surface.
///
/// The endpoint takes no query parameters. The seller is the token's user, so
/// there is no id for this service to send.
class SellerDashboardService {
  const SellerDashboardService(this._apiClient);

  final ApiClient _apiClient;

  Future<SellerDashboard> load() {
    return _apiClient.get<SellerDashboard>(
      SellerDashboardEndpoints.summary,
      parse: (Object? data) =>
          SellerDashboard.fromJson(_asObject(data, 'GET /seller/dashboard')),
    );
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
