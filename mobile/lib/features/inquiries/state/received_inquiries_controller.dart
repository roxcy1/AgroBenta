import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../models/received_inquiry.dart';
import '../../../models/received_inquiry_page.dart';
import '../../../repositories/inquiry_repository.dart';
import 'received_inquiries_state.dart';

/// Presentation logic for the seller's received inquiries.
///
/// The mechanics mirror `TransactionsController`: generation-guarded first
/// pages, a `loadMore` guard, and a `refresh` that keeps results on screen.
/// There is no search, no filter and no re-sort: the server returns newest
/// first, and re-ordering a page locally would disagree with the pagination it
/// computed over the same order.
///
/// The seller is never named here. `GET /seller/inquiries` resolves the inbox
/// from the token, so this controller has no id to carry and no way to point
/// the list at another account.
class ReceivedInquiriesController extends ChangeNotifier {
  ReceivedInquiriesController(this._repository);

  final InquiryRepository _repository;

  ReceivedInquiriesState _state = const ReceivedInquiriesState();
  ReceivedInquiriesState get state => _state;

  bool _disposed = false;
  bool _loadingMore = false;
  int _generation = 0;

  /// Loads the first page, unless one is already in flight.
  Future<void> loadInitial() {
    if (_state.status == ReceivedInquiriesStatus.loading ||
        _state.status == ReceivedInquiriesStatus.refreshing) {
      return Future<void>.value();
    }
    return _loadFirstPage();
  }

  /// Requests the next page, if the server has one and none is in flight.
  Future<void> loadMore() async {
    if (_loadingMore || !_state.hasMorePages) {
      return;
    }
    if (_state.status != ReceivedInquiriesStatus.ready) {
      return;
    }

    _loadingMore = true;
    _set(
      _state.copyWith(
        status: ReceivedInquiriesStatus.loadingMore,
        clearLoadMoreError: true,
      ),
    );

    try {
      final ReceivedInquiryPage page = await _repository.listReceived(
        page: _state.currentPage + 1,
      );
      if (_disposed) {
        return;
      }
      _set(
        _state.copyWith(
          status: ReceivedInquiriesStatus.ready,
          inquiries: <ReceivedInquiry>[..._state.inquiries, ...page.inquiries],
          pagination: page.pagination,
        ),
      );
    } on ApiException catch (error) {
      if (_disposed) {
        return;
      }
      _set(
        _state.copyWith(
          status: ReceivedInquiriesStatus.ready,
          loadMoreErrorMessage: error.message,
        ),
      );
    } on Object {
      if (_disposed) {
        return;
      }
      _set(
        _state.copyWith(
          status: ReceivedInquiriesStatus.ready,
          loadMoreErrorMessage: 'Something went wrong. Please try again.',
        ),
      );
    } finally {
      _loadingMore = false;
    }
  }

  /// Re-queries page 1 while keeping what is on screen.
  Future<void> refresh() => _loadFirstPage(keepResults: true);

  Future<void> _loadFirstPage({bool keepResults = false}) async {
    final int generation = ++_generation;

    _set(
      _state.copyWith(
        status: keepResults
            ? ReceivedInquiriesStatus.refreshing
            : ReceivedInquiriesStatus.loading,
        clearInquiries: !keepResults,
        clearError: true,
        clearLoadMoreError: true,
        clearRefreshError: true,
      ),
    );

    try {
      final ReceivedInquiryPage page = await _repository.listReceived();
      if (_disposed || generation != _generation) {
        return;
      }
      _set(
        _state.copyWith(
          status: ReceivedInquiriesStatus.ready,
          inquiries: page.inquiries,
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
                status: ReceivedInquiriesStatus.ready,
                refreshErrorMessage: error.message,
              )
            : _state.copyWith(
                status: ReceivedInquiriesStatus.failed,
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
                status: ReceivedInquiriesStatus.ready,
                refreshErrorMessage: message,
              )
            : _state.copyWith(
                status: ReceivedInquiriesStatus.failed,
                errorMessage: message,
              ),
      );
    }
  }

  void _set(ReceivedInquiriesState next) {
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
