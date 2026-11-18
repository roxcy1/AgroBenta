import 'dart:convert';
import 'dart:typed_data';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/core/network/api_exception.dart';
import 'package:agrobenta_mobile/models/user.dart';
import 'package:agrobenta_mobile/services/profile_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';

import '../support/auth_fakes.dart';

/// A one-pixel PNG, small enough to keep the encoded multipart body readable.
final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

void main() {
  group('uploadAvatar', () {
    test(
      'sends the picked bytes as avatar instead of a filesystem path',
      () async {
        final FakeTokenStore tokenStore = FakeTokenStore('1|test-mobile-token');
        final List<http.Request> captured = <http.Request>[];
        final ApiClient client = ApiClient(
          tokenStorage: tokenStore,
          httpClient: MockClient((http.Request request) async {
            captured.add(request);
            return http.Response(
              jsonEncode(
                successEnvelope(
                  data: userJson(
                    avatarUrl: 'http://localhost:8001/storage/avatars/7/a.png',
                  ),
                ),
              ),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }),
        );

        // The bytes are the source of truth: `readAsBytes` must not fall back to
        // opening `path`. On Flutter Web the picker's `path` is not a filesystem
        // path at all, which is why the service cannot use
        // `MultipartFile.fromPath`.
        final User updated = await ProfileService(client).uploadAvatar(
          XFile.fromData(
            _pngBytes,
            path: 'avatar.png',
            name: 'avatar.png',
            mimeType: 'image/png',
          ),
        );

        final http.Request sent = captured.single;
        expect(sent.method, 'POST');
        expect(sent.url.path, '/api/profile/avatar');
        expect(sent.headers['Authorization'], 'Bearer 1|test-mobile-token');
        expect(
          sent.headers['content-type'],
          startsWith('multipart/form-data; boundary='),
        );

        // Latin-1, not UTF-8: the body carries raw file bytes.
        final String body = latin1.decode(sent.bodyBytes);
        expect(RegExp(r'name="avatar"').hasMatch(body), isTrue);
        expect(body, contains('filename="avatar.png"'));

        expect(
          updated.avatarUrl,
          'http://localhost:8001/storage/avatars/7/a.png',
        );
      },
    );

    test('keeps the server validation message on a 422', () async {
      const String message =
          'The avatar field must not be greater than 5120 kilobytes.';
      final ApiClient client = ApiClient(
        tokenStorage: FakeTokenStore('1|test-mobile-token'),
        httpClient: MockClient(
          (http.Request request) async => http.Response(
            jsonEncode(
              validationErrorBody(
                errors: <String, Object>{
                  'avatar': <String>[message],
                },
              ),
            ),
            422,
            headers: <String, String>{'content-type': 'application/json'},
          ),
        ),
      );

      await expectLater(
        ProfileService(client).uploadAvatar(
          XFile.fromData(_pngBytes, path: 'avatar.png', name: 'avatar.png'),
        ),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiErrorKind.validation,
              )
              .having(
                (ApiException error) =>
                    error.validationErrors['avatar']?.single,
                'validation message',
                message,
              ),
        ),
      );
    });
  });
}
