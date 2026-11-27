import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/realtime/realtime_event.dart';
import '../../../core/realtime/refresh_coalescer.dart';
import '../../../models/inquiry_list_item.dart';
import '../../../repositories/inquiry_repository.dart';

/// Lifecycle of the Messages "Inquiries" tab.
enum ActiveInquiriesStatus { initial, loading, ready, failed }

/// The immutable state of the active-inquiry list.
@immutable
class ActiveInquiriesState {
  const ActiveInquiriesState({
    this.status = ActiveInquiriesStatus.initial,
    this.items = const <InquiryListItem>[],
    this.errorMessage,
  });

  final ActiveInquiriesStatus status;
  final List<InquiryListItem> items;
  final String? errorMessage;

  bool get isLoading =>
      status == ActiveInquiriesStatus.initial ||
      status == ActiveInquiriesStatus.loading;

  ActiveInquiriesState copyWith({
    ActiveInquiriesStatus? status,
    List<InquiryListItem>? items,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ActiveInquiriesState(
      status: status ?? this.status,
      items: items ?? this.items,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Presentation logic for the Messages "Inquiries" tab.
///
/// The list is always scoped by the active Account Mode: passing `buyer`
/// returns the caller's inquiries as a buyer, `seller` their received ones.
/// The server already excludes inquiries converted to an accepted
/// transaction, so the tab never re-filters or hides records on its own.
class ActiveInquiriesController extends ChangeNotifier {
  ActiveInquiriesController(
    this._repository, {
    required this.role,
    this.realtimeEvents,
    this.connection,
  }) {
    _realtimeSubscription = realtimeEvents?.listen(_onRealtimeEvent);
    _connectionSubscription = connection?.listen(_onConnectionChanged);
  }

  final InquiryRepository _repository;

  /// `buyer` or `seller` — the side the inbox is showing.
  final String role;

  /// The session's decoded events. A new inquiry or an offer update changes
  /// this tab (including `latest_offer`), so it re-loads.
  final Stream<RealtimeEvent>? realtimeEvents;

  /// Connection changes; a reconnect re-fetches to recover missed inquiries.
  final Stream<bool>? connection;

  StreamSubscription<RealtimeEvent>? _realtimeSubscription;
  StreamSubscription<bool>? _connectionSubscription;

  ActiveInquiriesState _state = const ActiveInquiriesState();
  ActiveInquiriesState get state => _state;

  bool _disposed = false;
  bool _loading = false;

  /// Incremented per read; a response from a superseded read is discarded.
  int _generation = 0;

  /// Background refreshes requested by real-time events and reconnects.
  late final RefreshCoalescer _backgroundRefresh = RefreshCoalescer(
    _refreshInBackground,
    isBusy: () => _loading,
  );

  Future<void> load() async {
    if (_loading) {
      return;
    }
    _loading = true;
    _set(
      _state.copyWith(status: ActiveInquiriesStatus.loading, clearError: true),
    );
    try {
      await _fetch(silent: false);
    } finally {
      _loading = false;
      _backgroundRefresh.settled();
    }
  }

  Future<void> refresh() => load();

  /// Re-reads the list without the loading state; a failure keeps the rows on
  /// screen (the next event or reconnect retries).
  Future<void> _refreshInBackground() => _fetch(silent: true);

  /// The one read behind [load] and [_refreshInBackground]. A [silent] read
  /// leaves the state untouched on failure.
  Future<void> _fetch({required bool silent}) async {
    final int generation = ++_generation;
    bool stale() => _disposed || generation != _generation;
    try {
      final List<InquiryListItem> items = await _repository.listActive(
        role: role,
      );
      if (stale()) {
        return;
      }
      _set(
        _state.copyWith(
          status: ActiveInquiriesStatus.ready,
          items: items,
          clearError: true,
        ),
      );
    } on ApiException catch (error) {
      if (!stale() && !silent) {
        _set(
          _state.copyWith(
            status: ActiveInquiriesStatus.failed,
            errorMessage: error.message,
          ),
        );
      }
    } on Object {
      if (!stale() && !silent) {
        _set(
          _state.copyWith(
            status: ActiveInquiriesStatus.failed,
            errorMessage: 'Something went wrong. Please try again.',
          ),
        );
      }
    }
  }

  void _set(ActiveInquiriesState next) {
    if (_disposed) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  /// A new inquiry or an offer update moves this side's inquiry list.
  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.name == 'inquiry.created' ||
        event.name == 'offer.created' ||
        event.name == 'offer.updated') {
      _backgroundRefresh.request();
    }
  }

  /// A reconnect may have missed inquiries while the socket was down.
  void _onConnectionChanged(bool connected) {
    if (connected) {
      _backgroundRefresh.request();
    }
  }

  @override
  void dispose() {
    _backgroundRefresh.dispose();
    _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _disposed = true;
    super.dispose();
  }
}
