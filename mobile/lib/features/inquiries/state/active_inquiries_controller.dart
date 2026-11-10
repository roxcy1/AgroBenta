import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/realtime/realtime_event.dart';
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

  Future<void> load() async {
    if (_loading) {
      return;
    }
    _loading = true;
    _set(
      _state.copyWith(status: ActiveInquiriesStatus.loading, clearError: true),
    );

    try {
      final List<InquiryListItem> items = await _repository.listActive(
        role: role,
      );
      if (_disposed) {
        return;
      }
      _set(_state.copyWith(status: ActiveInquiriesStatus.ready, items: items));
    } on ApiException catch (error) {
      if (_disposed) {
        return;
      }
      _set(
        _state.copyWith(
          status: ActiveInquiriesStatus.failed,
          errorMessage: error.message,
        ),
      );
    } on Object {
      if (_disposed) {
        return;
      }
      _set(
        _state.copyWith(
          status: ActiveInquiriesStatus.failed,
          errorMessage: 'Something went wrong. Please try again.',
        ),
      );
    } finally {
      _loading = false;
    }
  }

  Future<void> refresh() => load();

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
      unawaited(refresh());
    }
  }

  /// A reconnect may have missed inquiries while the socket was down.
  void _onConnectionChanged(bool connected) {
    if (connected) {
      unawaited(refresh());
    }
  }

  @override
  void dispose() {
    _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _disposed = true;
    super.dispose();
  }
}
