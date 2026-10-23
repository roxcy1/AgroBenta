import 'dart:convert';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_controller.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_scope.dart';
import 'package:agrobenta_mobile/features/profile/state/profile_controller.dart';
import 'package:agrobenta_mobile/features/profile/state/profile_scope.dart';
import 'package:agrobenta_mobile/features/profile/view/change_password_screen.dart';
import 'package:agrobenta_mobile/features/profile/view/edit_profile_screen.dart';
import 'package:agrobenta_mobile/features/profile/view/profile_screen.dart';
import 'package:agrobenta_mobile/features/seller_verification/view/seller_verification_screen.dart';
import 'package:agrobenta_mobile/repositories/profile_repository.dart';
import 'package:agrobenta_mobile/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/auth_app_harness.dart';
import '../../support/auth_fakes.dart';
import '../../support/seller_verification_app_harness.dart';

/// The profile screen, which is where sign-out lives since it left the Home
/// screen. The auth controller is exercised through the real repository and a
/// mock transport, so the assertions cover what actually goes over the wire.
///
/// The screen now also renders the seller-verification card, so the tree needs
/// the `SellerVerificationScope` that `main.dart` installs; the harness answers
/// it with "never submitted".
void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  setUp(() {
    tokenStore = FakeTokenStore();
    recorded = <RecordedRequest>[];
  });

  /// Pumps the profile screen under a restored session. [handler] answers the
  /// auth transport — `/auth/me` for the restore and `/auth/logout` for the
  /// sign-out under test. The profile read itself goes through its own canned
  /// transport, as it is not the subject here.
  ///
  /// The actions below sit below the default 800×600 test fold, so the tap
  /// helpers scroll them into view and let the scroll land before tapping —
  /// `tap` hit-tests against the last laid-out geometry.
  Future<void> pumpProfile(
    WidgetTester tester, {
    required Future<http.Response> Function(RecordedRequest request) handler,
  }) async {
    final AuthController authController = AuthController(
      buildAuthRepository(tokenStore, handler, recorded: recorded),
    );
    addTearDown(authController.dispose);

    final ProfileRepository profileRepository = ProfileRepository(
      ProfileService(
        ApiClient(
          tokenStorage: tokenStore,
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode(successEnvelope(data: userJson())),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            ),
          ),
        ),
      ),
    );
    final ProfileController profileController = ProfileController(
      profileRepository,
    );
    addTearDown(profileController.dispose);

    tokenStore.token = 'stored-token';
    await authController.restoreSession();

    await tester.pumpWidget(
      AuthScope(
        controller: authController,
        child: NeverSubmittedVerificationScope(
          child: ProfileScope(
            repository: profileRepository,
            controller: profileController,
            child: const MaterialApp(home: ProfileScreen()),
          ),
        ),
      ),
    );
    await settleAuth(tester, frames: 12);
  }

  Future<void> tapAction(WidgetTester tester, String label) async {
    final Finder target = find.widgetWithText(ListTile, label);
    await tester.ensureVisible(target);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(target);
    await settleAuth(tester, frames: 12);
  }

  bool isDisabled(WidgetTester tester, String label) =>
      tester.widget<ListTile>(find.widgetWithText(ListTile, label)).onTap ==
      null;

  testWidgets('renders the caller, account mode and supported settings', (
    WidgetTester tester,
  ) async {
    await pumpProfile(
      tester,
      handler: (_) async => http.Response(
        jsonEncode(successEnvelope(data: userJson())),
        200,
      ),
    );

    // Identity comes from the API payload, never a hardcoded sample.
    expect(find.text('Ana Reyes'), findsOneWidget);
    expect(find.text('ana@example.test'), findsOneWidget);

    // Account mode reflects the server-granted capability.
    expect(find.text('Account Mode'), findsOneWidget);
    expect(find.text('Buyer Account'), findsOneWidget);

    // The seller entry point is present for a buyer.
    expect(find.text('Become a Seller'), findsOneWidget);
    expect(find.text('Start Seller Verification'), findsOneWidget);

    // Supported rows are tappable; the unimplemented ones are inert.
    expect(isDisabled(tester, 'Personal Information'), isFalse);
    expect(isDisabled(tester, 'Change Password'), isFalse);
    expect(isDisabled(tester, 'Address'), isTrue);
    expect(isDisabled(tester, 'Notification Settings'), isTrue);

    // Other: Help/Terms have no approved destination, Log Out is real.
    expect(isDisabled(tester, 'Help and Support'), isTrue);
    expect(isDisabled(tester, 'Terms and Policies'), isTrue);
    expect(isDisabled(tester, 'Log Out'), isFalse);
  });

  testWidgets('Personal Information opens the existing edit form', (
    WidgetTester tester,
  ) async {
    await pumpProfile(
      tester,
      handler: (_) async => http.Response(
        jsonEncode(successEnvelope(data: userJson())),
        200,
      ),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await settleAuth(tester, frames: 12);
    expect(find.byType(EditProfileScreen), findsOneWidget);

    Navigator.of(tester.element(find.byType(EditProfileScreen))).pop();
    await settleAuth(tester, frames: 12);

    await tapAction(tester, 'Personal Information');
    expect(find.byType(EditProfileScreen), findsOneWidget);
  });

  testWidgets('Change Password opens the existing password form', (
    WidgetTester tester,
  ) async {
    await pumpProfile(
      tester,
      handler: (_) async => http.Response(
        jsonEncode(successEnvelope(data: userJson())),
        200,
      ),
    );

    await tapAction(tester, 'Change Password');
    expect(find.byType(ChangePasswordScreen), findsOneWidget);
  });

  testWidgets('Become a Seller opens the existing verification flow', (
    WidgetTester tester,
  ) async {
    await pumpProfile(
      tester,
      handler: (_) async => http.Response(
        jsonEncode(successEnvelope(data: userJson())),
        200,
      ),
    );

    await tester.ensureVisible(find.text('Start Seller Verification'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Start Seller Verification'));
    await settleAuth(tester, frames: 12);

    expect(find.byType(SellerVerificationScreen), findsOneWidget);
  });

  testWidgets('signs out through the server and drops the token', (
    WidgetTester tester,
  ) async {
    await pumpProfile(
      tester,
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
        return http.Response(
          jsonEncode(successEnvelope(data: userJson())),
          200,
        );
      },
    );

    await tapAction(tester, 'Log Out');

    expect(tokenStore.token, isNull);
    expect(
      recorded.last.apiPath,
      '/auth/logout',
      reason: 'the token must be revoked server-side, not just forgotten',
    );
  });

  testWidgets('a sign-out failure keeps the session', (
    WidgetTester tester,
  ) async {
    await pumpProfile(
      tester,
      handler: (RecordedRequest entry) async {
        if (entry.apiPath == '/auth/logout') {
          throw http.ClientException('connection refused');
        }
        return http.Response(
          jsonEncode(successEnvelope(data: userJson())),
          200,
        );
      },
    );

    await tapAction(tester, 'Log Out');

    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.text('Ana Reyes'), findsOneWidget);
    expect(
      tokenStore.token,
      'stored-token',
      reason: 'a failed sign-out must not silently drop the session',
    );
  });
}
