import 'dart:convert';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/core/storage/token_store.dart';
import 'package:agrobenta_mobile/repositories/livestock_type_repository.dart';
import 'package:agrobenta_mobile/services/livestock_type_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Builds the canonical catalog transport for test harnesses that mount a
/// catalog consumer outside the application composition root.
LivestockTypeRepository buildLivestockTypeRepository(TokenStore tokenStore) {
  return LivestockTypeRepository(
    LivestockTypeService(
      ApiClient(
        tokenStorage: tokenStore,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object>{
              'data': <Map<String, String>>[
                <String, String>{'value': 'cattle', 'label': 'Cattle'},
                <String, String>{'value': 'carabao', 'label': 'Carabao'},
                <String, String>{'value': 'goat', 'label': 'Goat'},
                <String, String>{'value': 'swine', 'label': 'Swine'},
              ],
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          ),
        ),
      ),
    ),
  );
}
