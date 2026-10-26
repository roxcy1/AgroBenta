import '../../../models/pagination.dart';
import '../../../models/received_inquiry.dart';

/// Where the seller's received-inquiry list is in its request lifecycle.
///
/// This is presentation state only. It says nothing about an inquiry's
/// administrator-facing status, which the mobile API does not expose.
enum ReceivedInquiriesStatus {
  /// Constructed but nothing requested yet.
  initial,

  /// The first page is in flight and there is nothing to show yet.
  loading,

  /// At least one page is loaded. Another page may still be in flight.
  ready,

  /// A page after the first is in flight; results stay on screen.
  loadingMore,

  /// Page 1 re-queried while results are on screen (pull-to-refresh).
  refreshing,

  /// The first page failed. Nothing on screen to preserve.
  failed,
}

/// An immutable snapshot of everything the Received Inquiries screen renders.
class ReceivedInquiriesState {
  const ReceivedInquiriesState({
    this.status = ReceivedInquiriesStatus.initial,
    this.inquiries = const <ReceivedInquiry>[],
    this.pagination,
    this.errorMessage,
    this.loadMoreErrorMessage,
    this.refreshErrorMessage,
  });

  final ReceivedInquiriesStatus status;

  /// Every inquiry loaded so far, in the server's order.
  final List<ReceivedInquiry> inquiries;

  /// Pagination for the most recent page received.
  final Pagination? pagination;

  /// A displayable failure for the whole list.
  final String? errorMessage;

  /// A displayable failure for a subsequent page.
  final String? loadMoreErrorMessage;

  /// A displayable failure for a pull-to-refresh that kept stale results.
  final String? refreshErrorMessage;

  int get currentPage => pagination?.currentPage ?? 0;

  bool get hasMorePages => pagination?.hasNextPage ?? false;

  bool get isEmpty =>
      status == ReceivedInquiriesStatus.ready && inquiries.isEmpty;

  bool get isBusy =>
      status == ReceivedInquiriesStatus.loading ||
      status == ReceivedInquiriesStatus.loadingMore ||
      status == ReceivedInquiriesStatus.refreshing;

  ReceivedInquiriesState copyWith({
    ReceivedInquiriesStatus? status,
    List<ReceivedInquiry>? inquiries,
    Pagination? pagination,
    String? errorMessage,
    String? loadMoreErrorMessage,
    String? refreshErrorMessage,
    bool clearError = false,
    bool clearLoadMoreError = false,
    bool clearRefreshError = false,
    bool clearInquiries = false,
  }) {
    return ReceivedInquiriesState(
      status: status ?? this.status,
      inquiries: clearInquiries
          ? const <ReceivedInquiry>[]
          : (inquiries ?? this.inquiries),
      pagination: pagination ?? this.pagination,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      loadMoreErrorMessage: clearLoadMoreError
          ? null
          : (loadMoreErrorMessage ?? this.loadMoreErrorMessage),
      refreshErrorMessage: clearRefreshError
          ? null
          : (refreshErrorMessage ?? this.refreshErrorMessage),
    );
  }

  @override
  String toString() =>
      'ReceivedInquiriesState(${status.name}, ${inquiries.length} inquiries, '
      'page $currentPage)';
}
