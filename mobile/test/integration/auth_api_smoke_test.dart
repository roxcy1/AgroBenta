@Tags(<String>['integration'])
library;

import 'package:agrobenta_mobile/core/config/app_config.dart';
import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/core/network/api_exception.dart';
import 'package:agrobenta_mobile/core/storage/token_store.dart';
import 'package:agrobenta_mobile/models/user.dart';
import 'package:agrobenta_mobile/repositories/auth_repository.dart';
import 'package:agrobenta_mobile/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercises a full session against the real API through the app's real
/// `ApiService`/`AuthRepository` stack — no mocks and no fakes.
///
/// This is the substitute for an on-device smoke test: it verifies that the
/// mobile client and the Laravel backend actually agree, which is the part
/// that unit tests and fakes cannot prove. It does not cover the
/// `10.0.2.2` loopback alias, which is an emulator platform fact.
///
/// Skipped by default so `flutter test` stays hermetic. To run it against the
/// local Docker stack:
///
/// ```sh
/// docker compose up -d
/// flutter test --dart-define=RUN_API_SMOKE=true \
///              --dart-define=API_BASE_URL=http://localhost:8001/api \
///              test/integration/auth_api_smoke_test.dart
/// ```
///
/// Each run registers a throwaway account, because the API offers no way to
/// delete one. The email is timestamped so repeat runs do not collide with the
/// `unique:users,email` rule.
///
/// The admin-refusal rule is deliberately *not* asserted here: it needs real
/// administrator credentials, and a wrong password would produce a `401` that
/// passes for the wrong reason. It is covered authoritatively by
/// `backend/tests/Feature/Auth/MobileAuthTest.php`.
const bool _runSmoke = bool.fromEnvironment('RUN_API_SMOKE');

/// Keeps the token in memory, so a smoke run can never touch a developer's
/// real device keystore.
class _MemoryTokenStore implements TokenStore {
  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String value) async => token = value;

  @override
  Future<void> clear() async => token = null;
}

void main() {
  group(
    'live API authentication smoke test',
    skip: _runSmoke
        ? false
        : 'Set --dart-define=RUN_API_SMOKE=true to run against a live API.',
    () {
      late _MemoryTokenStore tokenStore;
      late ApiClient apiClient;
      late AuthRepository repository;

      final String suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final String email = 'mobile.smoke.$suffix@example.test';
      const String password = 'smoke-test-password';

      setUpAll(() {
        // Printed so a failing run always says which stack it actually hit.
        // ignore: avoid_print
        print('Smoke target: ${AppConfig.apiBaseUrl}');
        tokenStore = _MemoryTokenStore();
        apiClient = ApiClient(tokenStorage: tokenStore);
        repository = AuthRepository(AuthService(apiClient), tokenStore);
      });

      tearDownAll(() => apiClient.close());

      test(
        'a full buyer session works against the real backend',
        // The dev stack serves each request in several seconds (uncached
        // Laravel config plus Docker), and this test makes seven sequential
        // calls, so the default 30s budget is not enough.
        timeout: const Timeout(Duration(minutes: 3)),
        () async {
          // 1. Register. The server decides the role and the seller capability;
          //    the client only sends the allow-listed fields.
          final User registered = await repository.register(
            name: 'Mobile Smoke',
            email: email,
            password: password,
            passwordConfirmation: password,
          );

          expect(registered.email, email);
          expect(registered.role, UserRole.user);
          expect(
            registered.sellerCapability,
            SellerCapability.buyer,
            reason: 'every registration must start as a buyer',
          );
          expect(tokenStore.token, isNotNull);

          // 2. The current user is loadable with the stored token.
          final User? restored = await repository.restoreSession();
          expect(restored, isNotNull);
          expect(restored!.id, registered.id);

          // 3. Sign out, then prove a wrong password is refused. This is checked
          //    while signed out because that is the only state the app can reach:
          //    the sign-in form is not shown to an authenticated user. A `401`
          //    clears the stored token, so the device is still signed out after.
          await repository.logout();
          expect(tokenStore.token, isNull);

          await expectLater(
            repository.login(email: email, password: 'definitely-wrong'),
            throwsA(
              isA<ApiException>()
                  .having(
                    (ApiException e) => e.kind,
                    'kind',
                    ApiErrorKind.unauthorized,
                  )
                  .having(
                    (ApiException e) => e.message,
                    'carries the server message',
                    isNotEmpty,
                  ),
            ),
          );
          expect(tokenStore.token, isNull);

          // 4. Signing in with the right password works and stores a token.
          final User signedIn = await repository.login(
            email: email,
            password: password,
          );
          expect(signedIn.id, registered.id);
          expect(tokenStore.token, isNotNull);
          final String? issuedToken = tokenStore.token;

          // 5. A duplicate registration is a 422 on the email field.
          await expectLater(
            repository.register(
              name: 'Mobile Smoke',
              email: email,
              password: password,
              passwordConfirmation: password,
            ),
            throwsA(
              isA<ApiException>()
                  .having(
                    (ApiException e) => e.kind,
                    'kind',
                    ApiErrorKind.validation,
                  )
                  .having(
                    (ApiException e) => e.validationErrors.containsKey('email'),
                    'has an email error',
                    isTrue,
                  ),
            ),
          );

          // 6. Logout revokes the token server-side. The response carries no
          //    `data` key, which is exactly the case ApiClient normalizes.
          await repository.logout();
          expect(tokenStore.token, isNull);

          // 7. The revoked token is dead, and is cleared rather than retried.
          tokenStore.token = issuedToken;

          expect(await repository.restoreSession(), isNull);
          expect(
            tokenStore.token,
            isNull,
            reason: 'a revoked token must be cleared from storage, not retried',
          );
        },
      );
    },
  );
}
