import 'package:flutter/foundation.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_exception.dart';
import '../../../models/seller_activity.dart';
import '../../../repositories/seller_activity_repository.dart';

/// Lifecycle of the seller activity feed.
enum SellerActivityStatus { initial, loading, ready, empty, failed }

/// Immutable state for the seller activity feed.
@immutable
class SellerActivityState {
  const SellerActivityState({
    this.status = SellerActivityStatus.initial,
    this.activities = const <SellerActivity>[],
    this.errorMessage,
  });

  final SellerActivityStatus status;
  final List<SellerActivity> activities;
  final String? errorMessage;

  bool get isLoading => status == SellerActivityStatus.loading;
  bool get isEmpty => status == SellerActivityStatus.empty;
  bool get hasFailed => status == SellerActivityStatus.failed;
}

/// Presentation logic for the seller's recent activity.
///
/// Independent from the dashboard and inquiry controllers: a failure here never
/// changes those sections. [load] is idempotent — a rebuild that calls it again
/// while loading, or once data/empty has arrived, issues no second request;
/// [refresh] and [retry] are the explicit ways to re-query.
class SellerActivityController extends ChangeNotifier {
  SellerActivityController(
    this._repository, {
    this.limit = SellerActivityEndpoints.defaultLimit,
  });

  final SellerActivityRepository _repository;

  /// Fixed page size for this controller's lifetime (server caps at 20).
  final int limit;

  SellerActivityState _state = const SellerActivityState();
  SellerActivityState get state => _state;

  bool _disposed = false;
  bool _loading = false;

  Future<void> load() {
    if (_loading ||
        _state.status == SellerActivityStatus.ready ||
        _state.status == SellerActivityStatus.empty) {
      return Future<void>.value();
    }
    return _fetch();
  }

  Future<void> retry() => _fetch();

  Future<void> refresh() => _fetch();

  Future<void> _fetch() async {
    if (_loading) {
      return;
    }
    _loading = true;
    _set(
      const SellerActivityState(status: SellerActivityStatus.loading),
    );

    try {
      final List<SellerActivity> activities = await _repository.latest(
        limit: limit,
      );
      if (_disposed) {
        return;
      }
      _set(
        SellerActivityState(
          status: activities.isEmpty
              ? SellerActivityStatus.empty
              : SellerActivityStatus.ready,
          activities: activities,
        ),
      );
    } on ApiException catch (error) {
      if (_disposed) {
        return;
      }
      _set(
        SellerActivityState(
          status: SellerActivityStatus.failed,
          errorMessage: error.message,
        ),
      );
    } on Object {
      if (_disposed) {
        return;
      }
      _set(
        const SellerActivityState(
          status: SellerActivityStatus.failed,
          errorMessage: 'Something went wrong. Please try again.',
        ),
      );
    } finally {
      _loading = false;
    }
  }

  void _set(SellerActivityState next) {
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
