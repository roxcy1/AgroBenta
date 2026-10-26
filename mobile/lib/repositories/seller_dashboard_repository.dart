import '../models/seller_dashboard.dart';
import '../services/seller_dashboard_service.dart';

/// Orchestration for the seller dashboard.
///
/// There is no pagination, filtering, or client-selected scope. The repository
/// exists so the controller depends on the mobile orchestration layer rather
/// than on the transport-facing service.
class SellerDashboardRepository {
  const SellerDashboardRepository(this._service);

  final SellerDashboardService _service;

  Future<SellerDashboard> load() => _service.load();
}
