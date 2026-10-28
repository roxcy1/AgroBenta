import 'dart:async';
import 'dart:convert';

import 'package:agrobenta_mobile/core/theme/app_colors.dart';
import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_controller.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_scope.dart';
import 'package:agrobenta_mobile/features/auth/view/sign_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';

/// Tests for the Log In screen's own behaviour.
///
/// The screen is pumped directly rather than through `AuthGate`: the gate's
/// success path renders the Buyer home screen, which pulls in scopes that have
/// nothing to do with signing in. The end-to-end paths — sign in, wrong
/// password, empty form, the registration round trip — are covered by
/// `auth_gate_test.dart`. This file covers what the gate cannot: the
/// presentation contract of the screen itself, especially the three controls
/// in the reference design that the backend does not support.
void main() {
  late FakeTokenStore tokenStore;

  setUp(() => tokenStore = FakeTokenStore());

  Future<AuthController> pumpSignIn(
    WidgetTester tester, {
    required Future<http.Response> Function(RecordedRequest request) handler,
    List<RecordedRequest>? recorded,
    VoidCallback? onRegister,
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
          child: SignInScreen(
            onRegister: onRegister ?? () {},
            onForgotPassword: () {},  // No-op: there is no forgot password flow
          ),
        ),
      ),
    );
    await tester.pump();

    return controller;
  }

  Future<void> fillFields(
    WidgetTester tester, {
    String email = 'ana@example.test',
  }) async {
    await tester.enterText(find.byType(TextFormField).at(0), email);
    await tester.enterText(find.byType(TextFormField).at(1), 'correct horse');
  }

  Future<void> tapLogIn(WidgetTester tester) async {
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Log In'));
    // A frame for the zero-duration scroll to reach the render tree — tap
    // hit-tests against the last laid-out geometry, not the new offset.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.widgetWithText(FilledButton, 'Log In'));
    await tester.pump();
  }

  /// Pumps a bounded number of frames. `pumpAndSettle` cannot be used while the
  /// submit spinner is on screen, because it schedules frames forever.
  Future<void> settle(WidgetTester tester, {int frames = 8}) async {
    for (int frame = 0; frame < frames; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  bool obscureOf(WidgetTester tester) => tester
      .widget<TextField>(
        find.descendant(
          of: find.byType(TextFormField).at(1),
          matching: find.byType(TextField),
        ),
      )
      .obscureText;

  testWidgets('renders the branded hero, welcome heading and sign-up link', (
    WidgetTester tester,
  ) async {
    await pumpSignIn(tester, handler: (_) async => fail('no request expected'));

    expect(find.text('AgroBenta'), findsOneWidget);
    expect(find.text('Buy. Sell. Grow. Together.'), findsOneWidget);
    expect(find.text('Welcome Back!'), findsOneWidget);
    expect(find.text('Sign in to continue'), findsOneWidget);
    expect(find.text("Don't have an account?"), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Sign Up'), findsOneWidget);
  });

  testWidgets('the password is hidden by default and the toggle reveals it', (
    WidgetTester tester,
  ) async {
    await pumpSignIn(tester, handler: (_) async => fail('no request expected'));

    expect(obscureOf(tester), isTrue, reason: 'hidden by default');

    // The control's label describes what the tap will do, so a screen-reader
    // user hears "Show password" rather than "eye".
    expect(find.byTooltip('Show password'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Show password'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();

    expect(obscureOf(tester), isFalse, reason: 'password is now visible');
    expect(find.byTooltip('Hide password'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();

    expect(obscureOf(tester), isTrue, reason: 'password hides again');
  });

  testWidgets('remember me and forgot password are shown but inert', (
    WidgetTester tester,
  ) async {
    final List<RecordedRequest> recorded = <RecordedRequest>[];
    await pumpSignIn(
      tester,
      recorded: recorded,
      handler: (_) async => fail('neither control may reach the API'),
    );

    // Remember-me: a Sanctum token has no "remembered" session to switch, so
    // the checkbox exists for layout only.
    final Checkbox checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.value, isFalse);
    expect(
      checkbox.onChanged,
      isNull,
      reason: 'remember-me must not imply it changes session persistence',
    );

    // Forgot Password?: styled green but with no interactive ancestor — no
    // approved password-recovery destination exists to navigate to.
    final Finder forgot = find.text('Forgot Password?');
    expect(forgot, findsOneWidget);
    expect(
      tester.widget<Text>(forgot).style?.color,
      AppColors.primary,
      reason: 'still styled as a link, per the reference layout',
    );
    expect(
      find.ancestor(of: forgot, matching: find.byType(TextButton)),
      findsNothing,
      reason: 'not tappable — there is no recovery endpoint',
    );
    expect(
      find.ancestor(of: forgot, matching: find.byType(InkWell)),
      findsNothing,
    );
    expect(
      find.ancestor(of: forgot, matching: find.byType(GestureDetector)),
      findsNothing,
    );
    expect(recorded, isEmpty);
  });

  testWidgets('social sign-in is shown but disabled', (
    WidgetTester tester,
  ) async {
    await pumpSignIn(tester, handler: (_) async => fail('no request expected'));

    expect(find.text('or continue with'), findsOneWidget);

    final List<OutlinedButton> social = tester
        .widgetList<OutlinedButton>(find.byType(OutlinedButton))
        .toList();
    expect(social, hasLength(2));
    for (final OutlinedButton button in social) {
      expect(
        button.onPressed,
        isNull,
        reason: 'Google/Facebook OAuth is not implemented by the backend',
      );
    }

    // The brand marks are the official glyphs, not approximations.
    expect(find.byIcon(FontAwesomeIcons.google.data), findsOneWidget);
    expect(find.byIcon(FontAwesomeIcons.facebook.data), findsOneWidget);
    expect(find.text('Social sign-in is not available yet.'), findsOneWidget);
  });

  testWidgets('a repeat tap during an active request is ignored', (
    WidgetTester tester,
  ) async {
    final Completer<http.Response> flight = Completer<http.Response>();
    final List<RecordedRequest> recorded = <RecordedRequest>[];
    final AuthController controller = await pumpSignIn(
      tester,
      recorded: recorded,
      handler: (_) => flight.future,
    );

    // Surrounding whitespace proves the email is trimmed before it leaves the
    // device, without changing the field names.
    await fillFields(tester, email: '  ana@example.test  ');
    await tapLogIn(tester);
    await settle(tester);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byType(FilledButton))
          .onPressed,
      isNull,
      reason: 'the button must be disabled while the request is in flight',
    );
    expect(recorded, hasLength(1));

    // A second tap while busy must not queue another request.
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pump();
    expect(recorded, hasLength(1));

    flight.complete(
      http.Response(
        jsonEncode(successEnvelope(data: authSessionJson())),
        200,
      ),
    );
    await settle(tester);

    expect(controller.state.isSignedIn, isTrue);
    expect(tokenStore.token, '1|test-mobile-token');
    expect(recorded.single.apiPath, '/auth/login');
    expect(recorded.single.body, <String, dynamic>{
      'email': 'ana@example.test',
      'password': 'correct horse',
    });
  });

  testWidgets('the Sign Up action hands back to the caller', (
    WidgetTester tester,
  ) async {
    bool handedBack = false;
    await pumpSignIn(
      tester,
      handler: (_) async => fail('no request expected'),
      onRegister: () => handedBack = true,
    );

    await tester.ensureVisible(find.widgetWithText(TextButton, 'Sign Up'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.widgetWithText(TextButton, 'Sign Up'));
    await tester.pump();

    expect(handedBack, isTrue);
  });
}
