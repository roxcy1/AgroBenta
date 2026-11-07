import 'package:flutter/foundation.dart';

import '../../../models/trinidad_location.dart';

enum TrinidadLocationStatus { initial, loading, ready, failed }

@immutable
class TrinidadLocationState {
  const TrinidadLocationState({
    this.status = TrinidadLocationStatus.initial,
    this.catalog,
    this.errorMessage,
  });

  final TrinidadLocationStatus status;
  final TrinidadLocationCatalog? catalog;
  final String? errorMessage;

  bool get isReady => status == TrinidadLocationStatus.ready;
  bool get isLoading =>
      status == TrinidadLocationStatus.initial ||
      status == TrinidadLocationStatus.loading;
  bool get hasFailed => status == TrinidadLocationStatus.failed;

  TrinidadLocationState copyWith({
    TrinidadLocationStatus? status,
    TrinidadLocationCatalog? catalog,
    String? errorMessage,
    bool clearError = false,
  }) {
    return TrinidadLocationState(
      status: status ?? this.status,
      catalog: catalog ?? this.catalog,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
