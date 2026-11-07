import 'dart:convert';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/core/storage/token_store.dart';
import 'package:agrobenta_mobile/features/trinidad_location/state/trinidad_location_controller.dart';
import 'package:agrobenta_mobile/features/trinidad_location/state/trinidad_location_scope.dart';
import 'package:agrobenta_mobile/repositories/trinidad_location_repository.dart';
import 'package:agrobenta_mobile/services/trinidad_location_service.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const List<String> trinidadBarangayNames = <String>[
  'Banlasan',
  'Bongbong',
  'Catoogan',
  'Guinobatan',
  'Hinlayagan Ilaud',
  'Hinlayagan Ilaya',
  'Kauswagan',
  'Kinan-oan',
  'La Union',
  'La Victoria',
  'Mabuhay Cabigohan',
  'Mahagbu',
  'Manuel M. Roxas',
  'Poblacion',
  'San Isidro',
  'San Vicente',
  'Santo Tomas',
  'Soom',
  'Tagum Norte',
  'Tagum Sur',
];

Map<String, dynamic> trinidadLocationCatalogJson() => <String, dynamic>{
  'region': 'Central Visayas (Region VII)',
  'province': 'Bohol',
  'municipality': 'Trinidad',
  'barangays': trinidadBarangayNames,
};

TrinidadLocationRepository buildTrinidadLocationRepository(
  TokenStore tokenStore,
) {
  return TrinidadLocationRepository(
    TrinidadLocationService(
      ApiClient(
        tokenStorage: tokenStore,
        httpClient: MockClient((http.Request request) async {
          if (!request.url.path.endsWith('/locations/trinidad/barangays')) {
            return http.Response('Not found', 404);
          }

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
    ),
  );
}

/// Installs a fake catalog above [child], matching the application scope shape.
class TrinidadLocationTestScope extends StatefulWidget {
  const TrinidadLocationTestScope({
    required this.tokenStore,
    required this.child,
    super.key,
  });

  final TokenStore tokenStore;
  final Widget child;

  @override
  State<TrinidadLocationTestScope> createState() =>
      _TrinidadLocationTestScopeState();
}

class _TrinidadLocationTestScopeState extends State<TrinidadLocationTestScope> {
  late final TrinidadLocationRepository _repository;
  late final TrinidadLocationController _controller;

  @override
  void initState() {
    super.initState();
    _repository = buildTrinidadLocationRepository(widget.tokenStore);
    _controller = TrinidadLocationController(_repository);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.ensureLoaded();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TrinidadLocationScope(
      repository: _repository,
      controller: _controller,
      child: widget.child,
    );
  }
}
