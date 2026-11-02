import 'dart:convert';

import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_controller.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_scope.dart';
import 'package:agrobenta_mobile/features/auth/view/auth_gate.dart';
import 'package:agrobenta_mobile/features/auth/view/forgot_password_screen.dart';
import 'package:agrobenta_mobile/features/auth/view/reset_password_screen.dart';
import 'package:agrobenta_mobile/features/auth/view/sign_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';

/// The forgot password journey through [AuthGate], from the sign-in link to the
/// confirmation back on the sign-in form.
void main() {
  const String email = 'ana@example.test';

  http.Response json(Object body, int status) =>
      http.Response(jsonEncode(body), status);

  http.Response ok() => json(<String, Object>{
    'success': true,
    'message': 'Done.',
  }, 200);

  void flowTest(String description, WidgetTesterCallback callback) {
    testWidgets(
      description,
      callback,
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  }

  Future<void> pumpGate(
    WidgetTester tester,
    Future<http.Response> Function(RecordedRequest request) handler, {
    List<RecordedRequest>? recorded,
  }) async {
    final AuthController controller = AuthController(
      buildAuthRepository(FakeTokenStore(), handler, recorded: recorded),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AuthScope(
          controller: controller,
          child: AuthGate(authenticatedView: (_) => const Text('Signed in')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String label) async {
    final Finder target = find.text(label);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> openForgotPassword(WidgetTester tester) async {
    await tapText(tester, 'Forgot Password?');
    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
  }

  Future<void> openResetPassword(WidgetTester tester) async {
    await openForgotPassword(tester);
    await tester.enterText(find.byType(TextFormField), ' $email ');
    await tapText(tester, 'Send reset code');
    expect(find.byType(ResetPasswordScreen), findsOneWidget);
  }

  /// The label is also the app bar title, so the button is found by type.
  Future<void> submitReset(WidgetTester tester) async {
    final Finder button = find.widgetWithText(FilledButton, 'Reset password');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> fillReset(
    WidgetTester tester, {
    String code = '123456',
    String password = 'newpassword1',
    String confirmation = 'newpassword1',
  }) async {
    final Finder fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), code);
    await tester.enterText(fields.at(1), password);
    await tester.enterText(fields.at(2), confirmation);
    await tester.pump();
  }

  group('forgot password screen', () {
    flowTest('an empty email is caught before the request', (
      WidgetTester tester,
    ) async {
      final List<RecordedRequest> recorded = <RecordedRequest>[];
      await pumpGate(tester, (_) async => ok(), recorded: recorded);

      await openForgotPassword(tester);
      await tapText(tester, 'Send reset code');

      expect(find.text('Enter your email address.'), findsOneWidget);
      expect(recorded, isEmpty);
    });

    flowTest('a valid email calls the server and opens the reset form', (
      WidgetTester tester,
    ) async {
      final List<RecordedRequest> recorded = <RecordedRequest>[];
      await pumpGate(tester, (_) async => ok(), recorded: recorded);

      await openResetPassword(tester);

      expect(recorded.single.method, 'POST');
      expect(recorded.single.apiPath, '/auth/forgot-password');
      expect(recorded.single.body, <String, dynamic>{'email': email});
    });

    flowTest('a 429 shows a cooldown message and stays on the screen', (
      WidgetTester tester,
    ) async {
      await pumpGate(
        tester,
        (_) async => json(<String, String>{'message': 'Too Many Attempts.'}, 429),
      );

      await openForgotPassword(tester);
      await tester.enterText(find.byType(TextFormField), email);
      await tapText(tester, 'Send reset code');

      expect(
        find.text('Too many attempts. Please try again in a minute.'),
        findsOneWidget,
      );
      expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    });

    flowTest('a server failure does not claim the code was sent', (
      WidgetTester tester,
    ) async {
      await pumpGate(
        tester,
        (_) async => json(<String, String>{'message': 'Boom'}, 500),
      );

      await openForgotPassword(tester);
      await tester.enterText(find.byType(TextFormField), email);
      await tapText(tester, 'Send reset code');

      expect(find.text('Something went wrong on the server.'), findsOneWidget);
      expect(find.byType(ResetPasswordScreen), findsNothing);
    });
  });

  group('reset password screen', () {
    flowTest('invalid input is caught before the request', (
      WidgetTester tester,
    ) async {
      final List<RecordedRequest> recorded = <RecordedRequest>[];
      await pumpGate(tester, (_) async => ok(), recorded: recorded);
      await openResetPassword(tester);
      recorded.clear();

      await fillReset(
        tester,
        code: '12a4',
        password: 'short',
        confirmation: 'different',
      );
      await submitReset(tester);

      expect(find.text('Enter the 6-digit code.'), findsOneWidget);
      expect(find.text('Use at least 8 characters.'), findsOneWidget);
      expect(find.text('The passwords do not match.'), findsOneWidget);
      expect(recorded, isEmpty);
    });

    flowTest('a wrong code shows the server message and stays put', (
      WidgetTester tester,
    ) async {
      const String message = 'The reset code is invalid or has expired.';
      await pumpGate(tester, (RecordedRequest request) async {
        return request.apiPath == '/auth/reset-password'
            ? json(<String, Object>{
                'success': false,
                'message': message,
                'errors': <String, List<String>>{
                  'token': <String>[message],
                },
              }, 422)
            : ok();
      });
      await openResetPassword(tester);

      await fillReset(tester);
      await submitReset(tester);

      expect(find.text(message), findsOneWidget);
      expect(find.byType(ResetPasswordScreen), findsOneWidget);
    });

    flowTest('a 429 shows a cooldown message', (WidgetTester tester) async {
      await pumpGate(tester, (RecordedRequest request) async {
        return request.apiPath == '/auth/reset-password'
            ? json(<String, String>{'message': 'Too Many Attempts.'}, 429)
            : ok();
      });
      await openResetPassword(tester);

      await fillReset(tester);
      await submitReset(tester);

      expect(
        find.text('Too many attempts. Please try again in a minute.'),
        findsOneWidget,
      );
    });

    flowTest('success returns to sign in with a confirmation', (
      WidgetTester tester,
    ) async {
      final List<RecordedRequest> recorded = <RecordedRequest>[];
      await pumpGate(tester, (_) async => ok(), recorded: recorded);
      await openResetPassword(tester);

      await fillReset(tester);
      await submitReset(tester);

      expect(recorded.last.apiPath, '/auth/reset-password');
      expect(recorded.last.body, <String, dynamic>{
        'email': email,
        'token': '123456',
        'password': 'newpassword1',
        'password_confirmation': 'newpassword1',
      });
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(
        find.text(
          'Your password has been reset. Sign in with your new password.',
        ),
        findsOneWidget,
      );
    });

    flowTest('back to sign in leaves the flow', (WidgetTester tester) async {
      await pumpGate(tester, (_) async => ok());
      await openResetPassword(tester);

      await tapText(tester, 'Back to sign in');

      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.textContaining('has been reset'), findsNothing);
    });
  });
}
