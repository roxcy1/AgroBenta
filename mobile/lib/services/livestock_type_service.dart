import '../core/constants/api_constants.dart';
import '../core/network/api_client.dart';
import '../core/utils/json_utils.dart';
import '../models/livestock_type.dart';

/// The approved livestock-type transport.
///
/// The endpoint is the one deliberate envelope exception in this app's contract:
/// it answers `{ "data": [...] }` without `success`/`message`. It therefore uses
/// [ApiClient.getRawJson] rather than the normal unwrapping [ApiClient.get].
class LivestockTypeService {
  const LivestockTypeService(this._client);

  final ApiClient _client;

  /// `GET /livestock-types` - the backend enum's four approved values.
  Future<List<LivestockType>> catalog() async {
    final Object? body = await _client.getRawJson(
      LivestockTypeEndpoints.catalog,
    );

    if (body is! Map) {
      throw FormatException(
        'A successful livestock-type response must be a JSON object, got '
        '${body.runtimeType}.',
      );
    }

    final Map<String, dynamic> map = body.cast<String, dynamic>();
    return readObjectList(map, 'data')
        .map(LivestockType.fromJson)
        .toList(growable: false);
  }
}
