import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../models/seller_dashboard.dart';
import '../../../repositories/seller_dashboard_repository.dart';
import 'seller_dashboard_state.dart';

/// Presentation logic for the seller dashboard.
///
/// The controller follows the generation-guarded first-load pattern used by the
/// received-inquiry list. A refresh keeps the previous dashboard on screen and
/// reports failure as a notice rather than replacing real data with an error.
class SellerDashboardController extends ChangeNotifier {
  SellerDashboardController(this._repository);

  final SellerDashboardRepository _repository;

  SellerDashboardState _state = const SellerDashboardState();
  SellerDashboardState get state => _state;

  bool _disposed = false;
  int _generation = 0;

  /// Loads the dashboard, unless a first load or refresh is in flight.
  Future<void> loadInitial() {
    if (_state.status == SellerDashboardStatus.loading ||
        _state.status == SellerDashboardStatus.refreshing) {
      return Future<void>.value();
    }
    return _load();
  }

  /// Retries after a first-load failure.
  Future<void> retry() {
    if (_state.status == SellerDashboardStatus.loading ||
        _state.status == SellerDashboardStatus.refreshing) {
      return Future<void>.value();
    }
    return _load();
  }

  /// Re-queries while keeping the current dashboard visible.
  Future<void> refresh() {
    if (_state.status == SellerDashboardStatus.loading ||
        _state.status == SellerDashboardStatus.refreshing) {
      return Future<void>.value();
    }
    return _load(keepResults: _state.dashboard != null);
  }

  Future<void> _load({bool keepResults = false}) async {
    final int generation = ++_generation;
    final bool preserve = keepResults && _state.dashboard != null;

    _set(
      _state.copyWith(
        status: preserve
            ? SellerDashboardStatus.refreshing
            : SellerDashboardStatus.loading,
        clearDashboard: !preserve,
        clearError: true,
        clearRefreshError: true,
      ),
    );

    try {
      final SellerDashboard dashboard = await _repository.load();
      if (_disposed || generation != _generation) {
        return;
      }
      _set(
        _state.copyWith(
          status: SellerDashboardStatus.ready,
          dashboard: dashboard,
        ),
      );
    } on ApiException catch (error) {
      if (_disposed || generation != _generation) {
        return;
      }
      // A 403 means the account is not an approved seller, so retrying cannot
      // help; say that rather than showing the server's wording.
      final String message = error.kind == ApiErrorKind.forbidden
          ? 'Seller Mode is not available for this account.'
          : error.message;
      _set(
        preserve
            ? _state.copyWith(
                status: SellerDashboardStatus.ready,
                refreshErrorMessage: message,
              )
            : _state.copyWith(
                status: SellerDashboardStatus.failed,
                errorMessage: message,
              ),
      );
    } on Object {
      if (_disposed || generation != _generation) {
        return;
      }
      const String message = 'Something went wrong. Please try again.';
      _set(
        preserve
            ? _state.copyWith(
                status: SellerDashboardStatus.ready,
                refreshErrorMessage: message,
              )
            : _state.copyWith(
                status: SellerDashboardStatus.failed,
                errorMessage: message,
              ),
      );
    }
  }

  void _set(SellerDashboardState next) {
    if (_disposed) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
