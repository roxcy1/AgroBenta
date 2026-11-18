import 'dart:convert';
import 'dart:typed_data';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/core/network/api_exception.dart';
import 'package:agrobenta_mobile/features/profile/state/profile_controller.dart';
import 'package:agrobenta_mobile/models/user.dart';
import 'package:agrobenta_mobile/repositories/profile_repository.dart';
import 'package:agrobenta_mobile/services/profile_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';

import '../../support/auth_fakes.dart';

const String _newAvatarUrl =
    'http://localhost:8001/storage/avatars/7/new-avatar.png';

ProfileController _controllerFor(
  Future<http.Response> Function(http.Request request) handler,
) {
  final ProfileController controller = ProfileController(
    ProfileRepository(
      ProfileService(
        ApiClient(
          tokenStorage: FakeTokenStore('1|test-mobile-token'),
          httpClient: MockClient(handler),
        ),
      ),
    ),
  );
  addTearDown(controller.dispose);
  return controller;
}

http.Response _jsonResponse(Object body, int statusCode) => http.Response(
  jsonEncode(body),
  statusCode,
  headers: <String, String>{'content-type': 'application/json'},
);

void main() {
  group('uploadAvatar', () {
    test('merges the returned user into state', () async {
      final ProfileController controller = _controllerFor((
        http.Request request,
      ) async {
        if (request.method == 'GET') {
          return _jsonResponse(successEnvelope(data: userJson()), 200);
        }
        return _jsonResponse(
          successEnvelope(data: userJson(avatarUrl: _newAvatarUrl)),
          200,
        );
      });

      await controller.load();
      expect(controller.state.user?.avatarUrl, isNull);

      final User updated = await controller.uploadAvatar(
        XFile.fromData(Uint8List.fromList(<int>[1, 2, 3]), path: 'avatar.png'),
      );

      expect(updated.avatarUrl, _newAvatarUrl);
      expect(controller.state.user?.avatarUrl, _newAvatarUrl);
    });

    test('rethrows a failure and keeps the loaded profile', () async {
      final ProfileController controller = _controllerFor((
        http.Request request,
      ) async {
        if (request.method == 'GET') {
          return _jsonResponse(successEnvelope(data: userJson()), 200);
        }
        return http.Response('Upload failed', 500);
      });

      await controller.load();
      final User? before = controller.state.user;
      expect(before, isNotNull);

      await expectLater(
        controller.uploadAvatar(
          XFile.fromData(
            Uint8List.fromList(<int>[1, 2, 3]),
            path: 'avatar.png',
          ),
        ),
        throwsA(isA<ApiException>()),
      );

      expect(controller.state.user, same(before));
      expect(controller.state.user?.avatarUrl, isNull);
    });
  });
}
