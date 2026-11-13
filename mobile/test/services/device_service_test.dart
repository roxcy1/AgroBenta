import 'package:agrobenta_mobile/core/constants/api_constants.dart';
import 'package:agrobenta_mobile/core/network/api_exception.dart';
import 'package:agrobenta_mobile/services/device_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/auth_fakes.dart';
import '../support/push_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  setUp(() {
    tokenStore = FakeTokenStore('1|mobile-token');
    recorded = <RecordedRequest>[];
  });

  test('POSTs only the token, with the bearer token', () async {
    final DeviceService service = buildDeviceService(
      tokenStore,
      (_) async => deviceRegisteredResponse(),
      recorded: recorded,
    );

    await service.register('fcm-token-1');

    expect(recorded, hasLength(1));
    expect(recorded.single.method, 'POST');
    expect(recorded.single.apiPath, DeviceEndpoints.register);
    expect(recorded.single.authorization, 'Bearer 1|mobile-token');
    expect(recorded.single.body, <String, dynamic>{'token': 'fcm-token-1'});
  });

  test('a failed registration surfaces as an ApiException', () async {
    final DeviceService service = buildDeviceService(
      tokenStore,
      (_) async => deviceRegisteredResponse(statusCode: 500),
    );

    expect(service.register('fcm-token-1'), throwsA(isA<ApiException>()));
  });
}
