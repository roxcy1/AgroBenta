import 'dart:convert';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/core/network/api_exception.dart';
import 'package:agrobenta_mobile/core/storage/token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// In-memory [TokenStore] so the client can be tested without the Android
/// Keystore or the iOS Keychain.
class _FakeTokenStore implements TokenStore {
  String? token;

  @override
  Future<void> clear() async => token = null;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String value) async => token = value;
}

void main() {
  late _FakeTokenStore tokenStore;
  late List<http.Request> captured;

  setUp(() {
    tokenStore = _FakeTokenStore();
    captured = <http.Request>[];
  });

  ApiClient buildClient(
    Future<http.Response> Function(http.Request request) handler,
  ) {
    return ApiClient(
      tokenStorage: tokenStore,
      httpClient: MockClient((http.Request request) async {
        captured.add(request);
        return handler(request);
      }),
    );
  }

  // `message` is always present here (possibly null). ApiEnvelope treats a
  // null message and an absent one identically, and the dedicated
  // "no message field" test below uses a raw literal to cover the absent case.
  Map<String, dynamic> envelope({Object? data, String? message}) =>
      <String, dynamic>{'success': true, 'message': message, 'data': data};

  group('request construction', () {
    test('attaches the bearer token when one is stored', () async {
      tokenStore.token = 'test-token-123';

      await buildClient(
        (http.Request request) async =>
            http.Response(jsonEncode(envelope(data: <String, dynamic>{})), 200),
      ).get<Object?>('/some/path', parse: (Object? data) => data);

      expect(captured.single.headers['Authorization'], 'Bearer test-token-123');
      expect(captured.single.headers['Accept'], 'application/json');
    });

    test('omits the Authorization header when signed out', () async {
      await buildClient(
        (http.Request request) async =>
            http.Response(jsonEncode(envelope(data: null)), 200),
      ).get<Object?>('/some/path', parse: (Object? data) => data);

      expect(captured.single.headers.containsKey('Authorization'), isFalse);
    });

    test('sets a JSON content type only when there is a body', () async {
      final ApiClient client = buildClient(
        (http.Request request) async =>
            http.Response(jsonEncode(envelope(data: null)), 200),
      );

      await client.get<Object?>('/a', parse: (Object? data) => data);
      await client.post<Object?>(
        '/b',
        body: <String, dynamic>{'email': 'a@b.test'},
        parse: (Object? data) => data,
      );

      expect(captured.first.headers.containsKey('Content-Type'), isFalse);
      expect(captured.last.headers['Content-Type'], 'application/json');
    });

    test('serialises the request body as JSON', () async {
      await buildClient(
        (http.Request request) async =>
            http.Response(jsonEncode(envelope(data: null)), 200),
      ).post<Object?>(
        '/b',
        body: <String, dynamic>{'email': 'a@b.test'},
        parse: (Object? data) => data,
      );

      expect(jsonDecode(captured.single.body), <String, dynamic>{
        'email': 'a@b.test',
      });
    });
  });

  group('envelope handling', () {
    test('unwraps data and surfaces the server message', () async {
      final ApiClient client = buildClient(
        (http.Request request) async => http.Response(
          jsonEncode(
            envelope(
              data: <String, dynamic>{'id': 7},
              message: 'Logged in successfully.',
            ),
          ),
          200,
        ),
      );

      final Map<String, dynamic> data = await client.get<Map<String, dynamic>>(
        '/a',
        parse: (Object? raw) => raw! as Map<String, dynamic>,
      );

      expect(data, <String, dynamic>{'id': 7});
    });

    test('accepts a response with no message field', () async {
      // Mirrors the admin `me` response, which omits `message`.
      final ApiClient client = buildClient(
        (http.Request request) async => http.Response(
          jsonEncode(<String, dynamic>{
            'success': true,
            'data': <String, dynamic>{'id': 1},
          }),
          200,
        ),
      );

      expect(
        await client.get<Object?>('/a', parse: (Object? data) => data),
        <String, dynamic>{'id': 1},
      );
    });

    test('treats 204 as an empty payload', () async {
      final ApiClient client = buildClient(
        (http.Request request) async => http.Response('', 204),
      );

      expect(
        await client.get<Object?>('/a', parse: (Object? data) => data),
        isNull,
      );
    });

    test('throws malformedResponse when the envelope is missing', () async {
      final ApiClient client = buildClient(
        (http.Request request) async =>
            http.Response(jsonEncode(<String, dynamic>{'id': 1}), 200),
      );

      await expectLater(
        client.get<Object?>('/a', parse: (Object? data) => data),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiErrorKind.malformedResponse,
          ),
        ),
      );
    });

    test('throws malformedResponse for non-JSON bodies', () async {
      final ApiClient client = buildClient(
        (http.Request request) async =>
            http.Response('<html>500</html>', 200),
      );

      await expectLater(
        client.get<Object?>('/a', parse: (Object? data) => data),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiErrorKind.malformedResponse,
          ),
        ),
      );
    });

    test('treats success:false on a 200 as a server error', () async {
      final ApiClient client = buildClient(
        (http.Request request) async => http.Response(
          jsonEncode(<String, dynamic>{
            'success': false,
            'message': 'Listing is not available.',
            'data': null,
          }),
          200,
        ),
      );

      await expectLater(
        client.get<Object?>('/a', parse: (Object? data) => data),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.kind, 'kind', ApiErrorKind.server)
              .having(
                (ApiException e) => e.message,
                'message',
                'Listing is not available.',
              ),
        ),
      );
    });
  });

  group('error mapping', () {
    Future<ApiException> captureStatus(
      int status,
      Object body, {
      bool withToken = true,
    }) async {
      if (withToken) {
        tokenStore.token = 'stale-token';
      }

      final ApiClient client = buildClient(
        (http.Request request) async =>
            http.Response(body is String ? body : jsonEncode(body), status),
      );

      try {
        await client.get<Object?>('/a', parse: (Object? data) => data);
        fail('Expected an ApiException for status $status');
      } on ApiException catch (error) {
        return error;
      }
    }

    test('401 is unauthorized, requires re-auth, and clears the token', () async {
      final ApiException error = await captureStatus(
        401,
        <String, dynamic>{'message': 'Unauthenticated.'},
      );

      expect(error.kind, ApiErrorKind.unauthorized);
      expect(error.requiresReauthentication, isTrue);
      expect(tokenStore.token, isNull);
    });

    test('a 401 while signed out reads as a rejected password', () async {
      // With no token stored, a 401 can only be about the submitted
      // credentials — it must not be reported as an ended session.
      final ApiClient client = buildClient(
        (http.Request request) async => http.Response('{}', 401),
      );

      await expectLater(
        client.post<Object?>('/auth/login', parse: (Object? data) => data),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException e) => e.kind,
                'kind',
                ApiErrorKind.unauthorized,
              )
              .having(
                (ApiException e) => e.message,
                'message',
                'The email or password is incorrect.',
              ),
        ),
      );
    });

    test('a server message always wins over the 401 fallback', () async {
      final ApiClient client = buildClient(
        (http.Request request) async => http.Response(
          jsonEncode(<String, dynamic>{
            'message': 'These credentials do not match our records.',
          }),
          401,
        ),
      );

      await expectLater(
        client.post<Object?>('/auth/login', parse: (Object? data) => data),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.message,
            'message',
            'These credentials do not match our records.',
          ),
        ),
      );
    });

    test('403 is forbidden and keeps the session', () async {
      // Laravel's `abort(403, 'Admin access is required.')` reaches a JSON
      // client as a JSON-encoded bare string, not an object.
      final ApiException error = await captureStatus(
        403,
        jsonEncode('Admin access is required.'),
      );

      expect(error.kind, ApiErrorKind.forbidden);
      expect(error.requiresReauthentication, isFalse);
      expect(error.message, 'Admin access is required.');
      expect(tokenStore.token, 'stale-token');
    });

    test('404 is notFound', () async {
      expect(
        (await captureStatus(404, <String, dynamic>{'message': 'Not found.'}))
            .kind,
        ApiErrorKind.notFound,
      );
    });

    test('422 is validation and extracts per-field errors', () async {
      final ApiException error = await captureStatus(422, <String, dynamic>{
        'message': 'The given data was invalid.',
        'errors': <String, dynamic>{
          'email': <String>['The email field is required.'],
          'password': <String>['The password field is required.'],
        },
      });

      expect(error.kind, ApiErrorKind.validation);
      expect(error.validationErrors['email'], <String>[
        'The email field is required.',
      ]);
      expect(error.validationErrors.keys, hasLength(2));
    });

    test('422 normalises a bare string error into a list', () async {
      final ApiException error = await captureStatus(422, <String, dynamic>{
        'errors': <String, dynamic>{'email': 'The email field is required.'},
      });

      expect(error.validationErrors['email'], <String>[
        'The email field is required.',
      ]);
    });

    test('429 is rateLimited', () async {
      expect(
        (await captureStatus(429, <String, dynamic>{})).kind,
        ApiErrorKind.rateLimited,
      );
    });

    test('5xx is server', () async {
      expect(
        (await captureStatus(500, <String, dynamic>{'message': 'Boom'})).kind,
        ApiErrorKind.server,
      );
    });

    test('falls back to a default message when the body carries none', () async {
      final ApiException error = await captureStatus(403, '');

      expect(error.message, isNotEmpty);
    });

    test('maps by status code when the error body is not JSON', () async {
      // Regression test. Nginx returns an HTML error page when the PHP
      // container is down, and Laravel's `abort(403, '...')` returns a bare
      // JSON string. Neither may be reported as a malformed success response —
      // the status code is the reliable signal.
      final ApiException forbidden = await captureStatus(
        403,
        '<html><body>403 Forbidden</body></html>',
      );
      expect(forbidden.kind, ApiErrorKind.forbidden);
      expect(forbidden.message, isNotEmpty);

      tokenStore.token = 'stale-token';
      final ApiClient client = buildClient(
        (http.Request request) async =>
            http.Response('<html>502 Bad Gateway</html>', 502),
      );

      await expectLater(
        client.get<Object?>('/a', parse: (Object? data) => data),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.kind, 'kind', ApiErrorKind.server)
              .having((ApiException e) => e.statusCode, 'statusCode', 502),
        ),
      );
    });
  });

  group('transport failures', () {
    test('surfaces ClientException as a network error', () async {
      final ApiClient client = ApiClient(
        tokenStorage: tokenStore,
        httpClient: MockClient((http.Request request) async {
          throw http.ClientException('Connection refused');
        }),
      );

      await expectLater(
        client.get<Object?>('/a', parse: (Object? data) => data),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiErrorKind.network,
          ),
        ),
      );
    });

    test('surfaces a timeout as a network error', () async {
      final ApiClient client = ApiClient(
        tokenStorage: tokenStore,
        timeout: const Duration(milliseconds: 20),
        httpClient: MockClient((http.Request request) async {
          await Future<void>.delayed(const Duration(seconds: 2));
          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        client.get<Object?>('/a', parse: (Object? data) => data),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiErrorKind.network,
          ),
        ),
      );
    });
  });

  group('success bodies without a data payload', () {
    test('parses a success envelope that omits data entirely', () async {
      // `POST /auth/logout` answers exactly this: a message and nothing else.
      final ApiClient client = buildClient(
        (http.Request request) async => http.Response(
          jsonEncode(<String, dynamic>{
            'success': true,
            'message': 'Logged out successfully.',
          }),
          200,
        ),
      );

      final Object? data = await client.post<Object?>(
        '/a',
        parse: (Object? data) => data,
      );

      expect(data, isNull);
    });

    test('does not mask a missing success field as an empty payload', () async {
      final ApiClient client = buildClient(
        (http.Request request) async =>
            http.Response(jsonEncode(<String, dynamic>{'id': 1}), 200),
      );

      await expectLater(
        client.get<Object?>('/a', parse: (Object? data) => data),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiErrorKind.malformedResponse,
          ),
        ),
      );
    });

    test('rejects a success body that is not a JSON object', () async {
      final ApiClient client = buildClient(
        (http.Request request) async =>
            http.Response(jsonEncode(<int>[1, 2, 3]), 200),
      );

      await expectLater(
        client.get<Object?>('/a', parse: (Object? data) => data),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiErrorKind.malformedResponse,
          ),
        ),
      );
    });
  });
}
