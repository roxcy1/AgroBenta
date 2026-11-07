import '../core/constants/api_constants.dart';
import '../core/network/api_client.dart';
import '../models/trinidad_location.dart';

class TrinidadLocationService {
  const TrinidadLocationService(this._client);

  final ApiClient _client;

  Future<TrinidadLocationCatalog> catalog() {
    return _client.get<TrinidadLocationCatalog>(
      TrinidadLocationEndpoints.catalog,
      parse: (Object? data) {
        if (data is Map<String, dynamic>) {
          return TrinidadLocationCatalog.fromJson(data);
        }
        if (data is Map) {
          return TrinidadLocationCatalog.fromJson(data.cast<String, dynamic>());
        }
        throw const FormatException(
          'Expected a JSON object for the Trinidad location catalog.',
        );
      },
    );
  }
}
