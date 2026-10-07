import 'dart:convert';

import 'package:agrobenta_mobile/core/network/api_exception.dart';
import 'package:agrobenta_mobile/models/user.dart';
import 'package:agrobenta_mobile/repositories/auth_repository.dart';
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

  AuthRepository repository(
    Future<http.Response> Function(RecordedRequest request) handler,
  ) => buildAuthRepository(tokenStore, handler, recorded: recorded);

  group('token persistence', () {
    test('login stores the returned token in secure storage', () async {
      final User user = await repository(
        (_) async => http.Response(
          jsonEncode(successEnvelope(data: authSessionJson())),
          200,
        ),
      ).login(email: 'ana@example.test', password: 'correct horse');

      expect(tokenStore.token, '1|test-mobile-token');
      expect(user.id, 7);
    });

    test('registration stores the returned token', () async {
      await repository(
        (_) async => http.Response(
          jsonEncode(successEnvelope(data: authSessionJson())),
          201,
        ),
      ).register(
        name: 'Ana Reyes',
        email: 'ana@example.test',
        password: 'correct horse',
        passwordConfirmation: 'correct horse',
      );

      expect(tokenStore.token, '1|test-mobile-token');
    });

    test('a failed login stores nothing', () async {
      await expectLater(
        repository(
          (_) async => http.Response(jsonEncode('Invalid credentials.'), 401),
        ).login(email: 'ana@example.test', password: 'wrong'),
        throwsA(isA<ApiException>()),
      );

      expect(tokenStore.token, isNull);
      expect(tokenStore.writeCount, 0);
    });

    test('an empty token is rejected rather than stored', () async {
      await expectLater(
        repository(
          (_) async => http.Response(
            jsonEncode(successEnvelope(data: authSessionJson(token: ''))),
            200,
          ),
        ).login(email: 'ana@example.test', password: 'correct horse'),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiErrorKind.malformedResponse,
          ),
        ),
      );

      expect(tokenStore.token, isNull);
    });
  });

  group('session restoration', () {
    test('loads the current user from a stored token', () async {
      tokenStore.token = 'stored-token';

      final User? user = await repository(
        (_) async =>
            http.Response(jsonEncode(successEnvelope(data: userJson())), 200),
      ).restoreSession();

      expect(user, isNotNull);
      expect(user!.id, 7);
      expect(user.sellerCapability, SellerCapability.buyer);
    });

    test('does not call the server when no token is stored', () async {
      final User? user = await repository(
        (_) async => fail('the API must not be called when signed out'),
      ).restoreSession();

      expect(user, isNull);
      expect(recorded, isEmpty);
    });

    test('an empty stored token counts as signed out', () async {
      tokenStore.token = '';

      final User? user = await repository(
        (_) async => fail('the API must not be called without a token'),
      ).restoreSession();

      expect(user, isNull);
    });

    test('a revoked token signs the device out and clears storage', () async {
      tokenStore.token = 'revoked-token';

      final User? user = await repository(
        (_) async => http.Response(jsonEncode('Unauthenticated.'), 401),
      ).restoreSession();

      expect(user, isNull);
      expect(tokenStore.token, isNull);
    });

    test('a network failure is reported, not treated as signed out', () async {
      tokenStore.token = 'stored-token';

      await expectLater(
        repository(
          (_) async => throw http.ClientException('connection refused'),
        ).restoreSession(),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiErrorKind.network,
          ),
        ),
      );

      // The token is still valid as far as the server is concerned, so it must
      // survive a dropped connection.
      expect(tokenStore.token, 'stored-token');
    });

    test('a 500 during restoration is reported, not swallowed', () async {
      tokenStore.token = 'stored-token';

      await expectLater(
        repository(
          (_) async => http.Response(jsonEncode('Server error.'), 500),
        ).restoreSession(),
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

  group('logout', () {
    test('revokes the token server-side and clears it locally', () async {
      tokenStore.token = 'stored-token';

      await repository(
        (_) async => http.Response(
          jsonEncode(<String, dynamic>{
            'success': true,
            'message': 'Logged out successfully.',
          }),
          200,
        ),
      ).logout();

      expect(recorded.single.apiPath, '/auth/logout');
      expect(recorded.single.authorization, 'Bearer stored-token');
      expect(tokenStore.token, isNull);
    });

    test('a 401 still ends the local session', () async {
      tokenStore.token = 'already-revoked';

      await repository(
        (_) async => http.Response(jsonEncode('Unauthenticated.'), 401),
      ).logout();

      expect(tokenStore.token, isNull);
    });

    test('a network failure keeps the token so the user can retry', () async {
      tokenStore.token = 'stored-token';

      await expectLater(
        repository(
          (_) async => throw http.ClientException('connection refused'),
        ).logout(),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.kind,
            'kind',
            ApiErrorKind.network,
          ),
        ),
      );

      expect(tokenStore.token, 'stored-token');
    });

    test('forgetLocalSession clears the token without a request', () async {
      tokenStore.token = 'stored-token';

      await repository(
        (_) async => fail('the API must not be called'),
      ).forgetLocalSession();

      expect(tokenStore.token, isNull);
      expect(recorded, isEmpty);
    });
  });
}
