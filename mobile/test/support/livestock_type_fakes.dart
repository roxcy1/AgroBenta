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
              'data': <Map<String, Object>>[
                <String, Object>{
                  'value': 'cattle',
                  'label': 'Cattle',
                  'breeds': <String>[
                    'Philippine Native Cattle',
                    'Brahman',
                    'Holstein Friesian',
                    'Brahman Cross',
                  ],
                },
                <String, Object>{
                  'value': 'carabao',
                  'label': 'Carabao',
                  'breeds': <String>[
                    'Philippine Native Carabao',
                    'Murrah',
                    'Native–Murrah Cross',
                  ],
                },
                <String, Object>{
                  'value': 'goat',
                  'label': 'Goat',
                  'breeds': <String>[
                    'Ubay/Boholano Native Goat',
                    'Boer',
                    'Anglo-Nubian',
                    'Saanen',
                  ],
                },
                <String, Object>{
                  'value': 'swine',
                  'label': 'Swine',
                  'breeds': <String>[
                    'Native Pig',
                    'Landrace',
                    'Large White (Yorkshire)',
                    'Duroc',
                    'Duroc–Landrace Cross',
                  ],
                },
                <String, Object>{
                  'value': 'chicken',
                  'label': 'Chicken',
                  'breeds': <String>[
                    'Boholano Native Chicken',
                    'Broiler',
                    'Layer',
                    'Improved Native Chicken',
                  ],
                },
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
