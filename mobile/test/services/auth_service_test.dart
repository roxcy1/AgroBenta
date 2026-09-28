import 'dart:convert';

import 'package:agrobenta_mobile/core/network/api_exception.dart';
import 'package:agrobenta_mobile/models/auth_session.dart';
import 'package:agrobenta_mobile/models/user.dart';
import 'package:agrobenta_mobile/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/auth_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  setUp(() {
    tokenStore = FakeTokenStore();
    recorded = <RecordedRequest>[];
  });

  group('register', () {
    test('POSTs the allow-listed fields to /auth/register', () async {
      final AuthService service = buildAuthService(
        tokenStore,
        (_) async => http.Response(
          jsonEncode(successEnvelope(data: authSessionJson())),
          201,
        ),
        recorded: recorded,
      );

      await service.register(
        name: 'Ana Reyes',
        email: 'ana@example.test',
        password: 'correct horse',
        passwordConfirmation: 'correct horse',
      );

      expect(recorded.single.method, 'POST');
      expect(recorded.single.apiPath, '/auth/register');
      expect(recorded.single.body, <String, dynamic>{
        'name': 'Ana Reyes',
        'email': 'ana@example.test',
        'password': 'correct horse',
        'password_confirmation': 'correct horse',
      });
    });

    test('never sends a server-owned field', () async {
      final AuthService service = buildAuthService(
        tokenStore,
        (_) async => http.Response(
          jsonEncode(successEnvelope(data: authSessionJson())),
          201,
        ),
        recorded: recorded,
      );

      await service.register(
        name: 'Ana Reyes',
        email: 'ana@example.test',
        password: 'correct horse',
        passwordConfirmation: 'correct horse',
        deviceName: 'Pixel',
      );

      // `role` and `seller_capability` must never appear in a request body:
      // a device that can send them can bypass seller verification.
      expect(recorded.single.body.containsKey('role'), isFalse);
      expect(recorded.single.body.containsKey('seller_capability'), isFalse);
      expect(recorded.single.body['device_name'], 'Pixel');
    });

    test('omits device_name when it was not supplied', () async {
      final AuthService service = buildAuthService(
        tokenStore,
        (_) async => http.Response(
          jsonEncode(successEnvelope(data: authSessionJson())),
          201,
        ),
        recorded: recorded,
      );

      await service.register(
        name: 'Ana Reyes',
        email: 'ana@example.test',
        password: 'correct horse',
        passwordConfirmation: 'correct horse',
      );

      expect(recorded.single.body.containsKey('device_name'), isFalse);
    });

    test('sends no Authorization header when signed out', () async {
      final AuthService service = buildAuthService(
        tokenStore,
        (_) async => http.Response(
          jsonEncode(successEnvelope(data: authSessionJson())),
          201,
        ),
        recorded: recorded,
      );

      await service.register(
        name: 'Ana Reyes',
        email: 'ana@example.test',
        password: 'correct horse',
        passwordConfirmation: 'correct horse',
      );

      expect(recorded.single.authorization, isNull);
    });

    test('surfaces a duplicate email as a field error', () async {
      final AuthService service = buildAuthService(
        tokenStore,
        (_) async => http.Response(
          jsonEncode(
            validationErrorBody(
              errors: <String, Object>{
                'email': <String>['The email has already been taken.'],
              },
            ),
          ),
          422,
        ),
      );

      await expectLater(
        service.register(
          name: 'Ana Reyes',
          email: 'ana@example.test',
          password: 'correct horse',
          passwordConfirmation: 'correct horse',
        ),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException e) => e.kind,
                'kind',
                ApiErrorKind.validation,
              )
              .having(
                (ApiException e) => e.validationErrors['email'],
                'email errors',
                <String>['The email has already been taken.'],
              ),
        ),
      );
    });
  });

  group('login', () {
    test('POSTs credentials to /auth/login', () async {
      final AuthService service = buildAuthService(
        tokenStore,
        (_) async => http.Response(
          jsonEncode(successEnvelope(data: authSessionJson())),
          200,
        ),
        recorded: recorded,
      );

      await service.login(
        email: 'ana@example.test',
        password: 'correct horse',
      );

      expect(recorded.single.method, 'POST');
      expect(recorded.single.apiPath, '/auth/login');
      expect(recorded.single.body, <String, dynamic>{
        'email': 'ana@example.test',
        'password': 'correct horse',
      });
    });

    test('returns the session and its user', () async {
      final AuthService service = buildAuthService(
        tokenStore,
        (_) async => http.Response(
          jsonEncode(successEnvelope(data: authSessionJson())),
          200,
        ),
      );

      final AuthSession session = await service.login(
        email: 'ana@example.test',
        password: 'correct horse',
      );

      expect(session.token, '1|test-mobile-token');
      expect(session.user.sellerCapability, SellerCapability.buyer);
    });

    test('maps bad credentials to unauthorized', () async {
      final AuthService service = buildAuthService(
        tokenStore,
        (_) async => http.Response(jsonEncode('Invalid credentials.'), 401),
      );

      await expectLater(
        service.login(email: 'ana@example.test', password: 'wrong'),
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
                'Invalid credentials.',
              ),
        ),
      );
    });

    test('maps an admin account to forbidden', () async {
      final AuthService service = buildAuthService(
        tokenStore,
        (_) async => http.Response(
          jsonEncode(
            'This account may not sign in to the mobile application.',
          ),
          403,
        ),
      );

      await expectLater(
        service.login(email: 'admin@example.test', password: 'secret123'),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException e) => e.kind,
                'kind',
                ApiErrorKind.forbidden,
              )
              .having(
                (ApiException e) => e.message,
                'message',
                'This account may not sign in to the mobile application.',
              ),
        ),
      );
    });
  });

  group('me', () {
    test('GETs /auth/me and returns the user', () async {
      tokenStore.token = 'stored-token';
      final AuthService service = buildAuthService(
        tokenStore,
        (_) async => http.Response(
          jsonEncode(successEnvelope(data: userJson())),
          200,
        ),
        recorded: recorded,
      );

      final User user = await service.me();

      expect(recorded.single.method, 'GET');
      expect(recorded.single.apiPath, '/auth/me');
      expect(recorded.single.authorization, 'Bearer stored-token');
      expect(user.email, 'ana@example.test');
    });
  });

  group('logout', () {
    test('POSTs to /auth/logout and tolerates a data-less body', () async {
      tokenStore.token = 'stored-token';
      final AuthService service = buildAuthService(
        tokenStore,
        (_) async => http.Response(
          // Exactly what the backend returns: no `data` key at all.
          jsonEncode(<String, dynamic>{
            'success': true,
            'message': 'Logged out successfully.',
          }),
          200,
        ),
        recorded: recorded,
      );

      await service.logout();

      expect(recorded.single.method, 'POST');
      expect(recorded.single.apiPath, '/auth/logout');
      expect(recorded.single.authorization, 'Bearer stored-token');
    });

    test('does not treat a malformed body as a failure', () async {
      tokenStore.token = 'stored-token';
      final AuthService service = buildAuthService(
        tokenStore,
        (_) async => http.Response('<html>502</html>', 502),
      );

      await expectLater(
        service.logout(),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiErrorKind.server,
          ),
        ),
      );
    });
  });
}
