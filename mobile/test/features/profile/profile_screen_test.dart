import 'dart:convert';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/features/account_mode/state/account_mode.dart';
import 'package:agrobenta_mobile/features/account_mode/state/account_mode_controller.dart';
import 'package:agrobenta_mobile/features/account_mode/state/account_mode_scope.dart';
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
    String sellerCapability = 'buyer',
  }) async {
    final Map<String, dynamic> currentUser = userJson(
      sellerCapability: sellerCapability,
    );

    final AuthController authController = AuthController(
      buildAuthRepository(tokenStore, handler, recorded: recorded),
    );
    addTearDown(authController.dispose);

    final AccountModeController accountModeController = AccountModeController(
      authController,
    );
    addTearDown(accountModeController.dispose);

    final ProfileRepository profileRepository = ProfileRepository(
      ProfileService(
        ApiClient(
          tokenStorage: tokenStore,
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode(successEnvelope(data: currentUser)),
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
        child: AccountModeScope(
          controller: accountModeController,
          child: NeverSubmittedVerificationScope(
            child: ProfileScope(
              repository: profileRepository,
              controller: profileController,
              child: const MaterialApp(home: ProfileScreen()),
            ),
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

    // Account mode always starts as Buyer Mode.
    expect(find.text('Account Mode'), findsOneWidget);
    expect(find.text('Buyer Mode'), findsOneWidget);
    expect(find.text('Seller Mode'), findsOneWidget);
    expect(find.text('Browse and purchase livestock.'), findsOneWidget);

    // The seller entry point is present for a buyer, but Seller Mode is not
    // available until verification is approved.
    expect(find.text('Become a Seller'), findsOneWidget);
    expect(find.text('Start Seller Verification'), findsOneWidget);
    final SegmentedButton<AccountMode> segmented = tester
        .widget<SegmentedButton<AccountMode>>(
          find.byType(SegmentedButton<AccountMode>),
        );
    expect(segmented.selected, <AccountMode>{AccountMode.buyer});
    expect(segmented.segments.last.enabled, isFalse);

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

  testWidgets('a verified seller can switch between Buyer and Seller Mode', (
    WidgetTester tester,
  ) async {
    await pumpProfile(
      tester,
      sellerCapability: 'seller',
      handler: (_) async => http.Response(
        jsonEncode(successEnvelope(data: userJson(sellerCapability: 'seller'))),
        200,
      ),
    );

    SegmentedButton<AccountMode> segmented() =>
        tester.widget<SegmentedButton<AccountMode>>(
          find.byType(SegmentedButton<AccountMode>),
        );

    expect(segmented().selected, <AccountMode>{AccountMode.buyer});
    expect(segmented().segments.last.enabled, isTrue);
    expect(find.text('Browse and purchase livestock.'), findsOneWidget);

    await tester.tap(find.text('Seller Mode'));
    await settleAuth(tester, frames: 12);

    expect(segmented().selected, <AccountMode>{AccountMode.seller});
    expect(
      find.text('You can list and manage your livestock.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Buyer Mode'));
    await settleAuth(tester, frames: 12);

    expect(segmented().selected, <AccountMode>{AccountMode.buyer});
    expect(find.text('Browse and purchase livestock.'), findsOneWidget);
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


  testWidgets('edit profile prompts for current password when email changes and sends it', (
    WidgetTester tester,
  ) async {
    final List<RecordedRequest> requests = <RecordedRequest>[];
    final ProfileRepository profileRepository = ProfileRepository(
      ProfileService(
        ApiClient(
          tokenStorage: tokenStore,
          httpClient: MockClient((RecordedRequest request) async {
            requests.add(request);
            if (request.method == 'PUT' && request.apiPath == '/profile') {
              return http.Response(
                jsonEncode(successEnvelope(
                  data: userJson(email: 'new@example.test'),
                )),
                200,
                headers: <String, String>{'content-type': 'application/json'},
              );
            }
            return http.Response(
              jsonEncode(successEnvelope(data: userJson())),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }),
        ),
      ),
    );
    final ProfileController profileController = ProfileController(profileRepository);
    addTearDown(profileController.dispose);

    final AuthController authController = AuthController(
      buildAuthRepository(tokenStore, (_) async => http.Response(jsonEncode(successEnvelope(data: userJson())), 200), recorded: recorded),
    );
    addTearDown(authController.dispose);
    final AccountModeController accountModeController = AccountModeController(authController);
    addTearDown(accountModeController.dispose);

    tokenStore.token = 'stored-token';
    await authController.restoreSession();

    await tester.pumpWidget(
      AuthScope(
        controller: authController,
        child: AccountModeScope(
          controller: accountModeController,
          child: NeverSubmittedVerificationScope(
            child: ProfileScope(
              repository: profileRepository,
              controller: profileController,
              child: const MaterialApp(home: EditProfileScreen()),
            ),
          ),
        ),
      ),
    );
    await settleAuth(tester, frames: 12);

    await tester.enterText(find.widgetWithText(TextFormField, 'Email address'), 'new@example.test');
    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm your password'), findsOneWidget);

    // Cancel prevents submission
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(requests.where((r) => r.method == 'PUT' && r.apiPath == '/profile').isEmpty, isTrue);

    // Try again and confirm
    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'password123');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    final RecordedRequest putReq = requests.firstWhere((r) => r.method == 'PUT' && r.apiPath == '/profile');
    final Map<String, dynamic> body = jsonDecode(putReq.body) as Map<String, dynamic>;
    expect(body['email'], 'new@example.test');
    expect(body['current_password'], 'password123');
  });

  testWidgets('edit profile does not require current password when email unchanged', (
    WidgetTester tester,
  ) async {
    final List<RecordedRequest> requests = <RecordedRequest>[];
    final ProfileRepository profileRepository = ProfileRepository(
      ProfileService(
        ApiClient(
          tokenStorage: tokenStore,
          httpClient: MockClient((RecordedRequest request) async {
            requests.add(request);
            if (request.method == 'PUT' && request.apiPath == '/profile') {
              return http.Response(
                jsonEncode(successEnvelope(
                  data: userJson(name: 'New Name'),
                )),
                200,
                headers: <String, String>{'content-type': 'application/json'},
              );
            }
            return http.Response(
              jsonEncode(successEnvelope(data: userJson())),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }),
        ),
      ),
    );
    final ProfileController profileController = ProfileController(profileRepository);
    addTearDown(profileController.dispose);

    final AuthController authController = AuthController(
      buildAuthRepository(tokenStore, (_) async => http.Response(jsonEncode(successEnvelope(data: userJson())), 200), recorded: recorded),
    );
    addTearDown(authController.dispose);
    final AccountModeController accountModeController = AccountModeController(authController);
    addTearDown(accountModeController.dispose);

    tokenStore.token = 'stored-token';
    await authController.restoreSession();

    await tester.pumpWidget(
      AuthScope(
        controller: authController,
        child: AccountModeScope(
          controller: accountModeController,
          child: NeverSubmittedVerificationScope(
            child: ProfileScope(
              repository: profileRepository,
              controller: profileController,
              child: const MaterialApp(home: EditProfileScreen()),
            ),
          ),
        ),
      ),
    );
    await settleAuth(tester, frames: 12);

    await tester.enterText(find.widgetWithText(TextFormField, 'Full name'), 'New Name');
    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm your password'), findsNothing);
    final RecordedRequest putReq = requests.firstWhere((r) => r.method == 'PUT' && r.apiPath == '/profile');
    final Map<String, dynamic> body = jsonDecode(putReq.body) as Map<String, dynamic>;
    expect(body.containsKey('current_password'), isFalse);
  });

  testWidgets('edit profile displays server current_password validation error', (
    WidgetTester tester,
  ) async {
    final List<RecordedRequest> requests = <RecordedRequest>[];
    final ProfileRepository profileRepository = ProfileRepository(
      ProfileService(
        ApiClient(
          tokenStorage: tokenStore,
          httpClient: MockClient((RecordedRequest request) async {
            requests.add(request);
            if (request.method == 'PUT' && request.apiPath == '/profile') {
              return http.Response(
                jsonEncode(<String, dynamic>{
                  'success': false,
                  'message': 'The given data was invalid.',
                  'errors': <String, dynamic>{
                    'current_password': <String>['The current password is incorrect.'],
                  },
                }),
                422,
                headers: <String, String>{'content-type': 'application/json'},
              );
            }
            return http.Response(
              jsonEncode(successEnvelope(data: userJson())),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }),
        ),
      ),
    );
    final ProfileController profileController = ProfileController(profileRepository);
    addTearDown(profileController.dispose);

    final AuthController authController = AuthController(
      buildAuthRepository(tokenStore, (_) async => http.Response(jsonEncode(successEnvelope(data: userJson())), 200), recorded: recorded),
    );
    addTearDown(authController.dispose);
    final AccountModeController accountModeController = AccountModeController(authController);
    addTearDown(accountModeController.dispose);

    tokenStore.token = 'stored-token';
    await authController.restoreSession();

    await tester.pumpWidget(
      AuthScope(
        controller: authController,
        child: AccountModeScope(
          controller: accountModeController,
          child: NeverSubmittedVerificationScope(
            child: ProfileScope(
              repository: profileRepository,
              controller: profileController,
              child: const MaterialApp(home: EditProfileScreen()),
            ),
          ),
        ),
      ),
    );
    await settleAuth(tester, frames: 12);

    await tester.enterText(find.widgetWithText(TextFormField, 'Email address'), 'new@example.test');
    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'wrong');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(find.text('The current password is incorrect.'), findsOneWidget);
  });

