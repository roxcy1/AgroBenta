import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_controller.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_scope.dart';
import 'package:agrobenta_mobile/features/auth/view/auth_gate.dart';
import 'package:agrobenta_mobile/features/home/view/buyer_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'auth_fakes.dart';
import 'seller_verification_app_harness.dart';

/// The signed-in destination the gate is given in tests. Kept as a function
/// rather than a widget so it matches how `main.dart` supplies it.
Widget _signedInView(BuildContext context) => const BuyerHomeScreen();

/// Pumps the real app shell — theme, `AuthScope`, `AuthGate` — over a mock
/// transport.
///
/// Nothing here touches the network or the platform keystore: the token store
/// is a fake and the HTTP client is a `MockClient`.
class AuthTestHarness {
  const AuthTestHarness._(this.controller, this.recorded);

  final AuthController controller;
  final List<RecordedRequest> recorded;

  static Future<AuthTestHarness> pump(
    WidgetTester tester, {
    required FakeTokenStore tokenStore,
    required Future<http.Response> Function(RecordedRequest request) handler,
  }) async {
    final List<RecordedRequest> recorded = <RecordedRequest>[];
    final AuthController controller = AuthController(
      buildAuthRepository(tokenStore, handler, recorded: recorded),
    );

    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        // The Home screen's seller card reads the seller verification scope, so
        // the harness has to carry it too — the same three scopes `main.dart`
        // installs. It is answered with "never submitted" because the auth tests
        // are not about seller verification, and the card must not need a
        // transport just to render.
        home: NeverSubmittedVerificationScope(
          child: AuthScope(
            controller: controller,
            child: const AuthGate(authenticatedView: _signedInView),
          ),
        ),
      ),
    );
    await settleAuth(tester);

    return AuthTestHarness._(controller, recorded);
  }
}

/// Pumps a bounded number of frames.
///
/// `pumpAndSettle` cannot be used here: a `CircularProgressIndicator` schedules
/// frames forever, so the tree never "settles" while a spinner is on screen.
/// A fixed number of pumps is enough to let the mock transport answer and the
/// resulting state change rebuild the tree.
Future<void> settleAuth(WidgetTester tester, {int frames = 8}) async {
  for (int frame = 0; frame < frames; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
