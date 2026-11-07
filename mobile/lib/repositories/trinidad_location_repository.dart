import '../models/trinidad_location.dart';
import '../services/trinidad_location_service.dart';

/// Caches the backend-owned location catalog for this app session.
class TrinidadLocationRepository {
  TrinidadLocationRepository(this._service);

  final TrinidadLocationService _service;
  TrinidadLocationCatalog? _cached;

  Future<TrinidadLocationCatalog> catalog() async {
    final TrinidadLocationCatalog? cached = _cached;
    if (cached != null) return cached;

    final TrinidadLocationCatalog loaded = await _service.catalog();
    _cached = loaded;
    return loaded;
  }
}
