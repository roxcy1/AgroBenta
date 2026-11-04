import 'package:flutter/foundation.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_exception.dart';
import '../../../models/pagination.dart';
import '../../../models/seller_activity.dart';
import '../../../repositories/seller_activity_repository.dart';

/// Lifecycle for the All Activities list.
enum SellerActivitiesStatus {
  initial,
  loading,
  ready,
  empty,
  failed,
  loadingMore,
  refreshing,
}

/// Immutable state of the All Activities screen.
@immutable
class SellerActivitiesState {
  const SellerActivitiesState({
    this.status = SellerActivitiesStatus.initial,
    this.activities = const <SellerActivity>[],
    this.pagination,
    this.category,
    this.from,
    this.to,
    this.errorMessage,
    this.loadMoreErrorMessage,
    this.refreshErrorMessage,
  });

  final SellerActivitiesStatus status;
  final List<SellerActivity> activities;
  final Pagination? pagination;
  final String? category;
  final DateTime? from;
  final DateTime? to;
  final String? errorMessage;
  final String? loadMoreErrorMessage;
  final String? refreshErrorMessage;

  bool get isInitialLoad =>
      status == SellerActivitiesStatus.initial ||
      status == SellerActivitiesStatus.loading;

  bool get hasMorePages => pagination?.hasNextPage ?? false;

  bool get hasActiveFilters => category != null || from != null || to != null;

  int get currentPage => pagination?.currentPage ?? 0;

  SellerActivitiesState copyWith({
    SellerActivitiesStatus? status,
    List<SellerActivity>? activities,
    Pagination? pagination,
    String? category,
    DateTime? fromDate,
    DateTime? toDate,
    String? errorMessage,
    String? loadMoreErrorMessage,
    String? refreshErrorMessage,
    bool clearCategory = false,
    bool clearDates = false,
    bool clearActivities = false,
    bool clearError = false,
    bool clearLoadMoreError = false,
    bool clearRefreshError = false,
  }) {
    return SellerActivitiesState(
      status: status ?? this.status,
      activities: clearActivities
          ? const <SellerActivity>[]
          : (activities ?? this.activities),
      pagination: clearActivities ? null : (pagination ?? this.pagination),
      category: clearCategory ? null : (category ?? this.category),
      from: clearDates ? null : (fromDate ?? from),
      to: clearDates ? null : (toDate ?? to),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      loadMoreErrorMessage: clearLoadMoreError
          ? null
          : (loadMoreErrorMessage ?? this.loadMoreErrorMessage),
      refreshErrorMessage: clearRefreshError
          ? null
          : (refreshErrorMessage ?? this.refreshErrorMessage),
    );
  }
}

/// Presentation logic for the seller's full activity history.
///
/// Filters and pagination are owned here so a page change never loses the
/// selected category or date range. First-page requests are generation-guarded;
/// [loadInitial] and [refresh] cannot overlap, which keeps the list from firing
/// duplicate requests on rebuilds.
class SellerActivitiesController extends ChangeNotifier {
  SellerActivitiesController(this._repository);

  final SellerActivityRepository _repository;

  SellerActivitiesState _state = const SellerActivitiesState();
  SellerActivitiesState get state => _state;

  bool _disposed = false;
  bool _loadingMore = false;
  int _generation = 0;

  Future<void> loadInitial() {
    if (_state.status == SellerActivitiesStatus.loading ||
        _state.status == SellerActivitiesStatus.refreshing) {
      return Future<void>.value();
    }
    return _loadFirstPage();
  }

  Future<void> retry() => _loadFirstPage();

  Future<void> refresh() => _loadFirstPage(keepResults: true);

  Future<void> loadMore() async {
    if (_loadingMore ||
        _state.status != SellerActivitiesStatus.ready ||
        !_state.hasMorePages) {
      return;
    }

    _loadingMore = true;
    final int generation = _generation;
    _set(
      _state.copyWith(
        status: SellerActivitiesStatus.loadingMore,
        clearLoadMoreError: true,
      ),
    );

    try {
      final SellerActivityPage page = await _repository.page(
        page: _state.currentPage + 1,
        perPage: SellerActivityEndpoints.defaultPageSize,
        category: _state.category,
        from: _state.from,
        to: _state.to,
      );
      if (_disposed || generation != _generation) {
        return;
      }
      _set(
        _state.copyWith(
          status: page.activities.isEmpty
              ? SellerActivitiesStatus.ready
              : SellerActivitiesStatus.ready,
          activities: <SellerActivity>[
            ..._state.activities,
            ...page.activities,
          ],
          pagination: page.pagination,
        ),
      );
    } on ApiException catch (error) {
      if (_disposed || generation != _generation) {
        return;
      }
      _set(
        _state.copyWith(
          status: SellerActivitiesStatus.ready,
          loadMoreErrorMessage: error.message,
        ),
      );
    } on Object {
      if (_disposed || generation != _generation) {
        return;
      }
      _set(
        _state.copyWith(
          status: SellerActivitiesStatus.ready,
          loadMoreErrorMessage: 'Something went wrong. Please try again.',
        ),
      );
    } finally {
      _loadingMore = false;
    }
  }

  Future<void> setCategory(String? category) async {
    if (category == _state.category) {
      return;
    }
    _set(_state.copyWith(category: category, clearCategory: category == null));
    await _loadFirstPage();
  }

  Future<void> setDateRange(DateTime? from, DateTime? to) async {
    if (from == _state.from && to == _state.to) {
      return;
    }
    _set(
      _state.copyWith(
        fromDate: from,
        toDate: to,
        clearDates: from == null && to == null,
      ),
    );
    await _loadFirstPage();
  }

  Future<void> clearFilters() async {
    if (!_state.hasActiveFilters) {
      return;
    }
    _set(
      _state.copyWith(
        category: null,
        fromDate: null,
        toDate: null,
        clearCategory: true,
        clearDates: true,
      ),
    );
    await _loadFirstPage();
  }

  Future<void> _loadFirstPage({bool keepResults = false}) async {
    final int generation = ++_generation;

    _set(
      _state.copyWith(
        status: keepResults
            ? SellerActivitiesStatus.refreshing
            : SellerActivitiesStatus.loading,
        clearActivities: !keepResults,
        clearError: true,
        clearLoadMoreError: true,
        clearRefreshError: true,
      ),
    );

    try {
      final SellerActivityPage page = await _repository.page(
        page: 1,
        perPage: SellerActivityEndpoints.defaultPageSize,
        category: _state.category,
        from: _state.from,
        to: _state.to,
      );
      if (_disposed || generation != _generation) {
        return;
      }
      _set(
        _state.copyWith(
          status: page.activities.isEmpty
              ? SellerActivitiesStatus.empty
              : SellerActivitiesStatus.ready,
          activities: page.activities,
          pagination: page.pagination,
        ),
      );
    } on ApiException catch (error) {
      if (_disposed || generation != _generation) {
        return;
      }
      _set(
        keepResults
            ? _state.copyWith(
                status: SellerActivitiesStatus.ready,
                refreshErrorMessage: error.message,
              )
            : _state.copyWith(
                status: SellerActivitiesStatus.failed,
                errorMessage: error.message,
              ),
      );
    } on Object {
      if (_disposed || generation != _generation) {
        return;
      }
      const String message = 'Something went wrong. Please try again.';
      _set(
        keepResults
            ? _state.copyWith(
                status: SellerActivitiesStatus.ready,
                refreshErrorMessage: message,
              )
            : _state.copyWith(
                status: SellerActivitiesStatus.failed,
                errorMessage: message,
              ),
      );
    }
  }

  void _set(SellerActivitiesState next) {
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
