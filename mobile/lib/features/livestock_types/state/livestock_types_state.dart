import 'package:flutter/foundation.dart';

import '../../../models/livestock_type.dart';

/// The lifecycle of the shared livestock-type catalog.
enum LivestockTypesStatus { initial, loading, ready, failed }

/// The immutable state of the catalog.
///
/// The list is empty until a successful load. Display code therefore has to
/// distinguish "catalog not known yet" from "catalog known and this value is not
/// in it": [labelFor] title-cases in the first case and appends
/// `(unsupported)` in the second.
@immutable
class LivestockTypesState {
  const LivestockTypesState({
    this.status = LivestockTypesStatus.initial,
    this.types = const <LivestockType>[],
    this.errorMessage,
  });

  final LivestockTypesStatus status;
  final List<LivestockType> types;
  final String? errorMessage;

  bool get isReady => status == LivestockTypesStatus.ready;

  bool get isLoading =>
      status == LivestockTypesStatus.initial ||
      status == LivestockTypesStatus.loading;

  bool get hasFailed => status == LivestockTypesStatus.failed;

  /// Whether [raw] is one of the approved values.
  bool isSupported(String raw) =>
      LivestockType.isSupported(raw, catalog: types);

  /// A supported value's label, or the historical value with
  /// `(unsupported)` once the catalog is known.
  String labelFor(String raw) =>
      LivestockType.displayLabel(raw, catalog: types);

  LivestockTypesState copyWith({
    LivestockTypesStatus? status,
    List<LivestockType>? types,
    String? errorMessage,
    bool clearError = false,
  }) {
    return LivestockTypesState(
      status: status ?? this.status,
      types: types ?? this.types,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
