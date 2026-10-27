import 'dart:convert';

import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_controller.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_scope.dart';
import 'package:agrobenta_mobile/features/auth/view/register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';

/// Tests for the Create Account screen's own behaviour.
///
/// The screen is pumped directly rather than through `AuthGate`: the gate's
/// success path renders the Buyer home screen, which pulls in scopes that have
/// nothing to do with registration and would make these assertions about the
/// wrong thing. The end-to-end path through the gate is covered by
/// `auth_gate_test.dart`.
void main() {
  late FakeTokenStore tokenStore;

  setUp(() => tokenStore = FakeTokenStore());

  Future<AuthController> pumpRegister(
    WidgetTester tester, {
    required Future<http.Response> Function(RecordedRequest request) handler,
    List<RecordedRequest>? recorded,
  }) async {
    final AuthController controller = AuthController(
      buildAuthRepository(tokenStore, handler, recorded: recorded),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AuthScope(
          controller: controller,
          child: RegisterScreen(onSignIn: () {}),
        ),
      ),
    );
    await tester.pump();

    return controller;
  }

  Future<void> fillFields(
    WidgetTester tester, {
    String password = 'correct horse',
    String confirmation = 'correct horse',
  }) async {
    await tester.enterText(find.byType(TextFormField).at(0), 'Ana Reyes');
    await tester.enterText(find.byType(TextFormField).at(1), 'ana@example.test');
    await tester.enterText(find.byType(TextFormField).at(2), password);
    await tester.enterText(find.byType(TextFormField).at(3), confirmation);
  }

  Future<void> giveConsent(WidgetTester tester) async {
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
  }

  Future<void> tapCreateAccount(WidgetTester tester) async {
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Create Account'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
    await tester.pump();
  }

  /// Pumps a bounded number of frames. `pumpAndSettle` cannot be used while the
  /// submit spinner is on screen, because it schedules frames forever.
  Future<void> settle(WidgetTester tester, {int frames = 8}) async {
    for (int frame = 0; frame < frames; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  bool obscureOf(WidgetTester tester, int index) => tester
      .widget<TextField>(
        find.descendant(
          of: find.byType(TextFormField).at(index),
          matching: find.byType(TextField),
        ),
      )
      .obscureText;

  testWidgets('renders the branded hero, heading and account link', (
    WidgetTester tester,
  ) async {
    await pumpRegister(tester, handler: (_) async => fail('no request expected'));

    expect(find.text('Create Your Account'), findsOneWidget);
    expect(find.text('AgroBenta'), findsOneWidget);
    expect(find.text('Buy. Sell. Grow. Together.'), findsOneWidget);
    expect(find.text('Already have an account?'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Log In'), findsOneWidget);
  });

  testWidgets('social sign-up is shown but disabled', (
    WidgetTester tester,
  ) async {
    await pumpRegister(tester, handler: (_) async => fail('no request expected'));

    final OutlinedButton google = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Google'),
    );
    final OutlinedButton facebook = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Facebook'),
    );

    expect(google.onPressed, isNull, reason: 'Google OAuth is not implemented');
    expect(
      facebook.onPressed,
      isNull,
      reason: 'Facebook OAuth is not implemented',
    );
    expect(find.text('Social sign-up is not available yet.'), findsOneWidget);
  });

  testWidgets('will not submit a valid form until consent is given', (
    WidgetTester tester,
  ) async {
    final List<RecordedRequest> recorded = <RecordedRequest>[];
    await pumpRegister(
      tester,
      recorded: recorded,
      handler: (_) async => fail('the API must not be called without consent'),
    );

    await fillFields(tester);
    await tapCreateAccount(tester);

    expect(recorded, isEmpty);
    expect(
      find.text('Please agree to the Terms and Privacy Policy to continue.'),
      findsOneWidget,
    );

    // Giving consent clears the error without a round trip.
    await giveConsent(tester);
    expect(
      find.text('Please agree to the Terms and Privacy Policy to continue.'),
      findsNothing,
    );
  });

  testWidgets('posts the allow-listed fields and signs in on success', (
    WidgetTester tester,
  ) async {
    final List<RecordedRequest> recorded = <RecordedRequest>[];
    final AuthController controller = await pumpRegister(
      tester,
      recorded: recorded,
      handler: (_) async => http.Response(
        jsonEncode(successEnvelope(data: authSessionJson())),
        201,
      ),
    );

    await fillFields(tester);
    await giveConsent(tester);
    await tapCreateAccount(tester);
    await settle(tester);

    expect(recorded, hasLength(1));
    expect(recorded.single.apiPath, '/auth/register');
    expect(recorded.single.body, <String, dynamic>{
      'name': 'Ana Reyes',
      'email': 'ana@example.test',
      'password': 'correct horse',
      'password_confirmation': 'correct horse',
    });
    expect(
      recorded.single.body.containsKey('seller_capability'),
      isFalse,
      reason: 'seller_capability is server-owned and must never be sent',
    );
    expect(recorded.single.body.containsKey('role'), isFalse);
    expect(controller.state.isSignedIn, isTrue);
    expect(tokenStore.token, '1|test-mobile-token');
  });

  testWidgets('a mismatched confirmation is caught before the request', (
    WidgetTester tester,
  ) async {
    final List<RecordedRequest> recorded = <RecordedRequest>[];
    await pumpRegister(
      tester,
      recorded: recorded,
      handler: (_) async => fail('the API must not be called on a mismatch'),
    );

    await fillFields(tester, confirmation: 'battery staple');
    await giveConsent(tester);
    await tapCreateAccount(tester);
    await settle(tester);

    expect(recorded, isEmpty);
    expect(find.text('The passwords do not match.'), findsOneWidget);
  });

  testWidgets('a server 422 is reported on the email field', (
    WidgetTester tester,
  ) async {
    await pumpRegister(
      tester,
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

    await fillFields(tester);
    await giveConsent(tester);
    await tapCreateAccount(tester);
    await settle(tester);

    expect(find.text('The email has already been taken.'), findsOneWidget);
    expect(tokenStore.token, isNull);
  });

  testWidgets('password and confirmation visibility toggle independently', (
    WidgetTester tester,
  ) async {
    await pumpRegister(tester, handler: (_) async => fail('no request expected'));

    expect(obscureOf(tester, 2), isTrue);
    expect(obscureOf(tester, 3), isTrue);

    // The first visibility control belongs to the Password field.
    await tester.ensureVisible(find.byIcon(Icons.visibility_outlined).first);
    await tester.tap(find.byIcon(Icons.visibility_outlined).first);
    await tester.pump();

    expect(obscureOf(tester, 2), isFalse, reason: 'password is now visible');
    expect(
      obscureOf(tester, 3),
      isTrue,
      reason: 'confirmation visibility is independent',
    );
  });
}
