import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../models/trinidad_location.dart';
import '../../../repositories/trinidad_location_repository.dart';
import 'trinidad_location_state.dart';

/// Session-scoped loader for the backend-owned Trinidad barangay catalog.
class TrinidadLocationController extends ChangeNotifier {
  TrinidadLocationController(this._repository);

  final TrinidadLocationRepository _repository;
  TrinidadLocationState _state = const TrinidadLocationState();
  TrinidadLocationState get state => _state;

  Future<void>? _inFlight;
  bool _disposed = false;

  Future<void> ensureLoaded() {
    if (_state.isReady) return Future<void>.value();
    return _load();
  }

  Future<void> retry() => _load(force: true);

  Future<void> _load({bool force = false}) {
    final Future<void>? inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    if (_state.isReady && !force) return Future<void>.value();

    final Future<void> future = _performLoad();
    _inFlight = future;
    return future;
  }

  Future<void> _performLoad() async {
    _set(
      _state.copyWith(status: TrinidadLocationStatus.loading, clearError: true),
    );
    try {
      final TrinidadLocationCatalog catalog = await _repository.catalog();
      if (_disposed) return;
      _set(
        _state.copyWith(
          status: TrinidadLocationStatus.ready,
          catalog: catalog,
          clearError: true,
        ),
      );
    } on ApiException catch (error) {
      if (_disposed) return;
      _set(
        _state.copyWith(
          status: TrinidadLocationStatus.failed,
          errorMessage: error.message,
        ),
      );
    } on Object {
      if (_disposed) return;
      _set(
        _state.copyWith(
          status: TrinidadLocationStatus.failed,
          errorMessage: 'Could not load Trinidad barangays. Please try again.',
        ),
      );
    } finally {
      _inFlight = null;
    }
  }

  void _set(TrinidadLocationState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
