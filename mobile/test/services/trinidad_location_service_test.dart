import 'dart:convert';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/services/trinidad_location_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/auth_fakes.dart';
import '../support/trinidad_location_fakes.dart';

void main() {
  test('reads the backend-owned Trinidad barangay catalog', () async {
    final TrinidadLocationService service = TrinidadLocationService(
      ApiClient(
        tokenStorage: FakeTokenStore('mobile-token'),
        httpClient: MockClient((http.Request request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/locations/trinidad/barangays');
          return http.Response(
            jsonEncode(<String, Object>{
              'success': true,
              'message': 'Trinidad location catalog retrieved.',
              'data': trinidadLocationCatalogJson(),
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }),
      ),
    );

    final catalog = await service.catalog();

    expect(catalog.region, 'Central Visayas (Region VII)');
    expect(catalog.province, 'Bohol');
    expect(catalog.municipality, 'Trinidad');
    expect(catalog.barangays, trinidadBarangayNames);
    expect(catalog.barangays, hasLength(20));
  });
}
