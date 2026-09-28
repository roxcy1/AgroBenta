import 'dart:convert';

import 'package:agrobenta_mobile/features/auth/view/register_screen.dart';
import 'package:agrobenta_mobile/features/auth/view/sign_in_screen.dart';
import 'package:agrobenta_mobile/features/home/view/buyer_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_app_harness.dart';
import '../../support/auth_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;

  setUp(() => tokenStore = FakeTokenStore());

  group('startup', () {
    testWidgets('shows the sign-in form when no session is stored', (
      WidgetTester tester,
    ) async {
      await AuthTestHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => fail('the API must not be called when signed out'),
      );

      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.byType(BuyerHomeScreen), findsNothing);
    });

    testWidgets('restores a stored session without flashing the form', (
      WidgetTester tester,
    ) async {
      tokenStore.token = 'stored-token';

      final AuthTestHarness harness = await AuthTestHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => http.Response(
          jsonEncode(successEnvelope(data: userJson())),
          200,
        ),
      );

      expect(find.byType(BuyerHomeScreen), findsOneWidget);
      expect(find.byType(SignInScreen), findsNothing);
      expect(
        harness.recorded.single.apiPath,
        '/auth/me',
        reason: 'the current user must be loaded from the API, not guessed',
      );
    });

    testWidgets('a revoked stored token lands on the sign-in form', (
      WidgetTester tester,
    ) async {
      tokenStore.token = 'revoked-token';

      await AuthTestHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => http.Response(jsonEncode('Unauthenticated.'), 401),
      );

      expect(find.byType(SignInScreen), findsOneWidget);
      expect(tokenStore.token, isNull);
    });

    testWidgets('an unreachable API offers a retry instead of a sign-out', (
      WidgetTester tester,
    ) async {
      tokenStore.token = 'stored-token';

      await AuthTestHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => throw http.ClientException('connection refused'),
      );

      expect(find.text('Could not sign you in'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
      expect(find.byType(SignInScreen), findsNothing);
      expect(
        tokenStore.token,
        'stored-token',
        reason: 'an unreachable API must not discard a valid session',
      );
    });

    testWidgets('the retry screen can abandon the session on purpose', (
      WidgetTester tester,
    ) async {
      tokenStore.token = 'stored-token';

      await AuthTestHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => throw http.ClientException('connection refused'),
      );

      await tester.tap(find.widgetWithText(TextButton, 'Sign out instead'));
      await settleAuth(tester);

      expect(find.byType(SignInScreen), findsOneWidget);
      expect(tokenStore.token, isNull);
    });
  });

  group('sign in', () {
    testWidgets('signs in and shows the Buyer home screen', (
      WidgetTester tester,
    ) async {
      final AuthTestHarness harness = await AuthTestHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => http.Response(
          jsonEncode(successEnvelope(data: authSessionJson())),
          200,
        ),
      );

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'ana@example.test',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'correct horse');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await settleAuth(tester);

      expect(find.byType(BuyerHomeScreen), findsOneWidget);
      expect(harness.recorded.single.apiPath, '/auth/login');
      expect(harness.recorded.single.body, <String, dynamic>{
        'email': 'ana@example.test',
        'password': 'correct horse',
      });
      expect(tokenStore.token, '1|test-mobile-token');
    });

    testWidgets('a wrong password shows the server message and stays put', (
      WidgetTester tester,
    ) async {
      await AuthTestHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => http.Response(
          jsonEncode('Invalid credentials.'),
          401,
        ),
      );

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'ana@example.test',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'wrong');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await settleAuth(tester);

      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.text('Invalid credentials.'), findsOneWidget);
      expect(tokenStore.token, isNull);
    });

    testWidgets('an empty form does not call the API', (
      WidgetTester tester,
    ) async {
      final AuthTestHarness harness = await AuthTestHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => fail('the API must not be called with no input'),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await settleAuth(tester);

      expect(harness.recorded, isEmpty);
      expect(find.text('Enter your email address.'), findsOneWidget);
    });

    testWidgets('the password is cleared after a failed attempt', (
      WidgetTester tester,
    ) async {
      await AuthTestHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => http.Response(jsonEncode('Invalid.'), 401),
      );

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'ana@example.test',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'wrong');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await settleAuth(tester);

      final TextField field = tester.widget<TextField>(
        find.descendant(
          of: find.byType(TextFormField).at(1),
          matching: find.byType(TextField),
        ),
      );
      expect(field.controller!.text, isEmpty);
    });
  });

  group('registration', () {
    testWidgets('registers a buyer and shows the home screen', (
      WidgetTester tester,
    ) async {
      final AuthTestHarness harness = await AuthTestHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => http.Response(
          jsonEncode(successEnvelope(data: authSessionJson())),
          201,
        ),
      );

      await tester.tap(find.widgetWithText(TextButton, 'Create an account'));
      await settleAuth(tester);
      expect(find.byType(RegisterScreen), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), 'Ana Reyes');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'ana@example.test',
      );
      await tester.enterText(
        find.byType(TextFormField).at(2),
        'correct horse',
      );
      await tester.enterText(
        find.byType(TextFormField).at(3),
        'correct horse',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await settleAuth(tester);

      expect(find.byType(BuyerHomeScreen), findsOneWidget);
      expect(harness.recorded.single.apiPath, '/auth/register');
      expect(harness.recorded.single.body, <String, dynamic>{
        'name': 'Ana Reyes',
        'email': 'ana@example.test',
        'password': 'correct horse',
        'password_confirmation': 'correct horse',
      });
      expect(
        harness.recorded.single.body.containsKey('seller_capability'),
        isFalse,
      );
      expect(harness.recorded.single.body.containsKey('role'), isFalse);
    });

    testWidgets('a duplicate email is reported on the email field', (
      WidgetTester tester,
    ) async {
      await AuthTestHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => http.Response(
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

      await tester.tap(find.widgetWithText(TextButton, 'Create an account'));
      await settleAuth(tester);
      await tester.enterText(find.byType(TextFormField).at(0), 'Ana Reyes');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'taken@example.test',
      );
      await tester.enterText(
        find.byType(TextFormField).at(2),
        'correct horse',
      );
      await tester.enterText(
        find.byType(TextFormField).at(3),
        'correct horse',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await settleAuth(tester);

      expect(find.byType(RegisterScreen), findsOneWidget);
      expect(find.text('The email has already been taken.'), findsOneWidget);
      expect(tokenStore.token, isNull);
    });

    testWidgets('a mismatched confirmation is caught before the request', (
      WidgetTester tester,
    ) async {
      final AuthTestHarness harness = await AuthTestHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => fail('the API must not be called on a mismatch'),
      );

      await tester.tap(find.widgetWithText(TextButton, 'Create an account'));
      await settleAuth(tester);
      await tester.enterText(find.byType(TextFormField).at(0), 'Ana Reyes');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'ana@example.test',
      );
      await tester.enterText(
        find.byType(TextFormField).at(2),
        'correct horse',
      );
      await tester.enterText(
        find.byType(TextFormField).at(3),
        'battery staple',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await settleAuth(tester);

      expect(find.text('The passwords do not match.'), findsOneWidget);
      expect(harness.recorded, isEmpty);
    });

    testWidgets('a too-short password is caught before the request', (
      WidgetTester tester,
    ) async {
      final AuthTestHarness harness = await AuthTestHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => fail('the API must not be called on a short password'),
      );

      await tester.tap(find.widgetWithText(TextButton, 'Create an account'));
      await settleAuth(tester);
      await tester.enterText(find.byType(TextFormField).at(0), 'Ana Reyes');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'ana@example.test',
      );
      await tester.enterText(find.byType(TextFormField).at(2), 'short');
      await tester.enterText(find.byType(TextFormField).at(3), 'short');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await settleAuth(tester);

      expect(find.text('Use at least 8 characters.'), findsOneWidget);
      expect(harness.recorded, isEmpty);
    });

    testWidgets('the form can go back to signing in', (
      WidgetTester tester,
    ) async {
      await AuthTestHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (_) async => fail('no request expected'),
      );

      await tester.tap(find.widgetWithText(TextButton, 'Create an account'));
      await settleAuth(tester);
      expect(find.byType(RegisterScreen), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'I already have an account'));
      await settleAuth(tester);

      expect(find.byType(SignInScreen), findsOneWidget);
    });
  });

  group('sign out', () {
    testWidgets('revokes the session and returns to the form', (
      WidgetTester tester,
    ) async {
      tokenStore.token = 'stored-token';

      final AuthTestHarness harness = await AuthTestHarness.pump(
        tester,
        tokenStore: tokenStore,
        handler: (RecordedRequest entry) async {
          if (entry.apiPath == '/auth/logout') {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'success': true,
                'message': 'Logged out successfully.',
              }),
              200,
            );
          }
          return http.Response(jsonEncode(successEnvelope(data: userJson())), 200);
        },
      );

      expect(find.byType(BuyerHomeScreen), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
      await settleAuth(tester);

      expect(find.byType(SignInScreen), findsOneWidget);
      expect(tokenStore.token, isNull);
      expect(
        harness.recorded.last.apiPath,
        '/auth/logout',
        reason: 'the token must be revoked server-side, not just forgotten',
      );
    });
  });
}
