import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../models/livestock_type.dart';
import '../../../repositories/livestock_type_repository.dart';
import 'livestock_types_state.dart';

/// Session-scoped presentation state for the approved livestock-type catalog.
///
/// The backend enum is the source of truth. This controller does not contain a
/// fallback list: the only values a seller can choose are the ones the server
/// returned. [ensureLoaded] is idempotent, so the signed-in shell can warm the
/// catalog while forms and filters can also ask for it without duplicating a
/// request.
class LivestockTypesController extends ChangeNotifier {
  LivestockTypesController(this._repository);

  final LivestockTypeRepository _repository;

  LivestockTypesState _state = const LivestockTypesState();
  LivestockTypesState get state => _state;

  Future<void>? _inFlight;
  bool _disposed = false;

  /// Loads the catalog unless it is already loaded or a request is in flight.
  Future<void> ensureLoaded() {
    if (_state.isReady) {
      return Future<void>.value();
    }
    return _load();
  }

  /// Tries again after a failure, even if a previous request is still recorded.
  Future<void> retry() => _load(force: true);

  Future<void> _load({bool force = false}) {
    final Future<void>? inFlight = _inFlight;
    if (inFlight != null) {
      return inFlight;
    }
    if (_state.isReady && !force) {
      return Future<void>.value();
    }

    final Future<void> future = _performLoad();
    _inFlight = future;
    return future;
  }

  Future<void> _performLoad() async {
    _set(
      _state.copyWith(status: LivestockTypesStatus.loading, clearError: true),
    );

    try {
      final List<LivestockType> types = await _repository.catalog();
      if (_disposed) {
        return;
      }
      _set(
        _state.copyWith(
          status: LivestockTypesStatus.ready,
          types: types,
          clearError: true,
        ),
      );
    } on ApiException catch (error) {
      if (_disposed) {
        return;
      }
      _set(
        _state.copyWith(
          status: LivestockTypesStatus.failed,
          errorMessage: error.message,
        ),
      );
    } on Object {
      if (_disposed) {
        return;
      }
      _set(
        _state.copyWith(
          status: LivestockTypesStatus.failed,
          errorMessage: 'Could not load livestock types. Please try again.',
        ),
      );
    } finally {
      _inFlight = null;
    }
  }

  void _set(LivestockTypesState next) {
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
