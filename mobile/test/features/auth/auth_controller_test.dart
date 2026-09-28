import 'dart:convert';

import 'package:agrobenta_mobile/features/auth/state/auth_controller.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_state.dart';
import 'package:agrobenta_mobile/models/user.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';

/// The controller is exercised through the real repository and a mock
/// transport rather than a stubbed repository, so the state transitions are
/// asserted against the behaviour the API actually has.
void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  setUp(() {
    tokenStore = FakeTokenStore();
    recorded = <RecordedRequest>[];
  });

  AuthController controllerFor(
    Future<http.Response> Function(RecordedRequest request) handler,
  ) => AuthController(
    buildAuthRepository(tokenStore, handler, recorded: recorded),
  );

  group('initial state', () {
    test('starts restoring, before any token has been checked', () {
      final AuthController controller = controllerFor(
        (_) async => fail('no request before restoreSession is called'),
      );

      expect(controller.state.status, AuthStatus.restoring);
      expect(controller.state.isRestoring, isTrue);
      expect(controller.state.user, isNull);
    });
  });

  group('session restoration', () {
    test('no stored token lands on the sign-in form', () async {
      final AuthController controller = controllerFor(
        (_) async => fail('the API must not be called when signed out'),
      );

      await controller.restoreSession();

      expect(controller.state.status, AuthStatus.signedOut);
      expect(controller.state.user, isNull);
    });

    test('a stored token loads the current user', () async {
      tokenStore.token = 'stored-token';
      final AuthController controller = controllerFor(
        (_) async => http.Response(
          jsonEncode(successEnvelope(data: userJson())),
          200,
        ),
      );

      await controller.restoreSession();

      expect(controller.state.status, AuthStatus.signedIn);
      expect(controller.state.isSignedIn, isTrue);
      expect(controller.state.user!.email, 'ana@example.test');
      expect(controller.state.user!.sellerCapability, SellerCapability.buyer);
    });

    test('a revoked token lands on the sign-in form', () async {
      tokenStore.token = 'revoked-token';
      final AuthController controller = controllerFor(
        (_) async => http.Response(jsonEncode('Unauthenticated.'), 401),
      );

      await controller.restoreSession();

      expect(controller.state.status, AuthStatus.signedOut);
      expect(controller.state.user, isNull);
      expect(tokenStore.token, isNull);
    });

    test('an unreachable API is a retryable state, not a sign-out', () async {
      tokenStore.token = 'stored-token';
      final AuthController controller = controllerFor(
        (_) async => throw http.ClientException('connection refused'),
      );

      await controller.restoreSession();

      expect(controller.state.status, AuthStatus.restoreFailed);
      expect(controller.state.isSignedIn, isFalse);
      expect(controller.state.errorMessage, isNotEmpty);
    });

    test('a retry after a failure can still restore the session', () async {
      tokenStore.token = 'stored-token';
      bool reachable = false;
      final AuthController controller = controllerFor((_) async {
        if (!reachable) {
          throw http.ClientException('connection refused');
        }
        return http.Response(jsonEncode(successEnvelope(data: userJson())), 200);
      });

      await controller.restoreSession();
      expect(controller.state.status, AuthStatus.restoreFailed);

      reachable = true;
      await controller.restoreSession();

      expect(controller.state.status, AuthStatus.signedIn);
      expect(controller.state.errorMessage, isNull);
    });
  });

  group('sign in', () {
    test('a successful sign-in establishes the session', () async {
      final AuthController controller = controllerFor(
        (_) async => http.Response(
          jsonEncode(successEnvelope(data: authSessionJson())),
          200,
        ),
      );

      final bool ok = await controller.signIn(
        email: 'ana@example.test',
        password: 'correct horse',
      );

      expect(ok, isTrue);
      expect(controller.state.status, AuthStatus.signedIn);
      expect(controller.state.isSubmitting, isFalse);
      expect(controller.state.user!.id, 7);
      expect(tokenStore.token, '1|test-mobile-token');
    });

    test('bad credentials surface the server message and stay signed out', () async {
      final AuthController controller = controllerFor(
        (_) async => http.Response(jsonEncode('Invalid credentials.'), 401),
      );

      final bool ok = await controller.signIn(
        email: 'ana@example.test',
        password: 'wrong',
      );

      expect(ok, isFalse);
      expect(controller.state.status, AuthStatus.signedOut);
      expect(controller.state.isSubmitting, isFalse);
      expect(controller.state.errorMessage, 'Invalid credentials.');
    });

    test('an admin account is told the app is not for it', () async {
      final AuthController controller = controllerFor(
        (_) async => http.Response(
          jsonEncode('This account may not sign in to the mobile application.'),
          403,
        ),
      );

      await controller.signIn(email: 'admin@example.test', password: 'secret');

      expect(
        controller.state.errorMessage,
        'This account may not sign in to the mobile application.',
      );
    });

    test('a throttled attempt explains itself', () async {
      final AuthController controller = controllerFor(
        (_) async => http.Response(jsonEncode('Too Many Attempts.'), 429),
      );

      await controller.signIn(email: 'ana@example.test', password: 'nope');

      expect(controller.state.errorMessage, 'Too Many Attempts.');
    });

    test('an unreachable API is reported rather than swallowed', () async {
      final AuthController controller = controllerFor(
        (_) async => throw http.ClientException('connection refused'),
      );

      await controller.signIn(email: 'ana@example.test', password: 'nope');

      expect(controller.state.status, AuthStatus.signedOut);
      expect(controller.state.errorMessage, contains('10.0.2.2'));
    });

    test('field errors are available to the form', () async {
      final AuthController controller = controllerFor(
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

      await controller.register(
        name: 'Ana Reyes',
        email: 'taken@example.test',
        password: 'correct horse',
        passwordConfirmation: 'correct horse',
      );

      expect(
        controller.state.errorFor('email'),
        'The email has already been taken.',
      );
    });

    test('a second submit while one is in flight is ignored', () async {
      int calls = 0;
      final AuthController controller = controllerFor((_) async {
        calls++;
        return http.Response(
          jsonEncode(successEnvelope(data: authSessionJson())),
          200,
        );
      });

      final Future<bool> first = controller.signIn(
        email: 'ana@example.test',
        password: 'correct horse',
      );
      final bool second = await controller.signIn(
        email: 'ana@example.test',
        password: 'correct horse',
      );
      await first;

      expect(second, isFalse);
      expect(calls, 1);
    });

    test('clearing the error resets the form', () async {
      final AuthController controller = controllerFor(
        (_) async => http.Response(jsonEncode('Invalid credentials.'), 401),
      );

      await controller.signIn(email: 'ana@example.test', password: 'wrong');
      expect(controller.state.errorMessage, isNotNull);

      controller.clearError();

      expect(controller.state.errorMessage, isNull);
      expect(controller.state.validationErrors, isEmpty);
    });
  });

  group('sign out', () {
    test('revokes the session and returns to the sign-in form', () async {
      tokenStore.token = 'stored-token';
      final AuthController controller = controllerFor((RecordedRequest entry) async {
        return http.Response(
          jsonEncode(
            successEnvelope(
              data: entry.apiPath == '/auth/logout' ? null : userJson(),
            ),
          ),
          200,
        );
      });

      await controller.restoreSession();
      expect(controller.state.status, AuthStatus.signedIn);

      final bool ok = await controller.signOut();

      expect(ok, isTrue);
      expect(controller.state.status, AuthStatus.signedOut);
      expect(controller.state.user, isNull);
      expect(tokenStore.token, isNull);
      expect(
        recorded.map((RecordedRequest e) => e.apiPath),
        containsAll(<String>['/auth/me', '/auth/logout']),
      );
    });

    test('a failed sign-out keeps the session and shows why', () async {
      tokenStore.token = 'stored-token';
      final AuthController controller = controllerFor((RecordedRequest entry) async {
        if (entry.apiPath == '/auth/logout') {
          throw http.ClientException('connection refused');
        }
        return http.Response(jsonEncode(successEnvelope(data: userJson())), 200);
      });

      await controller.restoreSession();
      final bool ok = await controller.signOut();

      expect(ok, isFalse);
      expect(controller.state.status, AuthStatus.signedIn);
      expect(controller.state.isSigningOut, isFalse);
      expect(controller.state.errorMessage, isNotNull);
      expect(tokenStore.token, 'stored-token');
    });

    test('forgetLocalSession abandons a session without a request', () async {
      tokenStore.token = 'stored-token';
      final AuthController controller = controllerFor(
        (_) async => fail('the API must not be called'),
      );

      await controller.forgetLocalSession();

      expect(controller.state.status, AuthStatus.signedOut);
      expect(tokenStore.token, isNull);
    });
  });
}
