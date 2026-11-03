import '../models/livestock_type.dart';
import '../services/livestock_type_service.dart';

/// Session-scoped access to the approved livestock-type catalog.
///
/// The catalog changes only when the backend enum changes, so one successful
/// fetch is cached for the session. A failed fetch is not cached, which lets the
/// retry controls on the form and filter ask again.
class LivestockTypeRepository {
  LivestockTypeRepository(this._service);

  final LivestockTypeService _service;

  List<LivestockType>? _cached;

  Future<List<LivestockType>> catalog() async {
    final List<LivestockType>? cached = _cached;
    if (cached != null) {
      return cached;
    }

    final List<LivestockType> types = await _service.catalog();
    _cached = types;
    return types;
  }
}
