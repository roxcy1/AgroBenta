import 'dart:convert';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/services/livestock_type_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/auth_fakes.dart';

void main() {
  test('parses the backend-owned canonical catalog', () async {
    final service = LivestockTypeService(
      ApiClient(
        tokenStorage: FakeTokenStore('mobile-token'),
        httpClient: MockClient((http.Request request) async {
          expect(request.url.path, '/api/livestock-types');
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'value': 'cattle',
                  'label': 'Cattle',
                  'breeds': ['Philippine Native Cattle', 'Brahman'],
                },
                {
                  'value': 'carabao',
                  'label': 'Carabao',
                  'breeds': ['Philippine Native Carabao', 'Murrah'],
                },
                {
                  'value': 'goat',
                  'label': 'Goat',
                  'breeds': ['Boer'],
                },
                {
                  'value': 'swine',
                  'label': 'Swine',
                  'breeds': ['Native Pig'],
                },
                {
                  'value': 'chicken',
                  'label': 'Chicken',
                  'breeds': [
                    'Boholano Native Chicken',
                    'Broiler',
                    'Layer',
                    'Improved Native Chicken',
                  ],
                },
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final types = await service.catalog();

    expect(types.map((type) => type.value), [
      'cattle',
      'carabao',
      'goat',
      'swine',
      'chicken',
    ]);
    expect(types.last.breeds, [
      'Boholano Native Chicken',
      'Broiler',
      'Layer',
      'Improved Native Chicken',
    ]);
    expect(types.last.breeds.contains('duck'), isFalse);
  });
}
