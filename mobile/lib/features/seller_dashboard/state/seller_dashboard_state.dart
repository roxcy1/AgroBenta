import '../../../models/seller_dashboard.dart';

/// Where the seller dashboard is in its request lifecycle.
enum SellerDashboardStatus {
  /// Constructed but nothing requested yet.
  initial,

  /// The first request is in flight, with nothing to show yet.
  loading,

  /// A dashboard has been loaded.
  ready,

  /// Re-querying while the previous dashboard stays on screen.
  refreshing,

  /// The first request failed, with nothing to show.
  failed,
}

/// An immutable snapshot of everything the seller dashboard renders.
class SellerDashboardState {
  const SellerDashboardState({
    this.status = SellerDashboardStatus.initial,
    this.dashboard,
    this.errorMessage,
    this.refreshErrorMessage,
  });

  final SellerDashboardStatus status;
  final SellerDashboard? dashboard;
  final String? errorMessage;

  /// A failed pull-to-refresh that kept the previous dashboard on screen.
  final String? refreshErrorMessage;

  bool get isEmpty =>
      status != SellerDashboardStatus.failed &&
      dashboard != null &&
      !dashboard!.hasActivity;

  bool get isBusy =>
      status == SellerDashboardStatus.loading ||
      status == SellerDashboardStatus.refreshing;

  SellerDashboardState copyWith({
    SellerDashboardStatus? status,
    SellerDashboard? dashboard,
    String? errorMessage,
    String? refreshErrorMessage,
    bool clearDashboard = false,
    bool clearError = false,
    bool clearRefreshError = false,
  }) {
    return SellerDashboardState(
      status: status ?? this.status,
      dashboard: clearDashboard ? null : (dashboard ?? this.dashboard),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      refreshErrorMessage: clearRefreshError
          ? null
          : (refreshErrorMessage ?? this.refreshErrorMessage),
    );
  }

  @override
  String toString() =>
      'SellerDashboardState(${status.name}, ${dashboard ?? 'no dashboard'})';
}
