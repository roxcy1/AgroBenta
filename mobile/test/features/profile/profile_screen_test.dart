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
import 'package:agrobenta_mobile/features/help_center/view/help_center_screen.dart';
import 'package:agrobenta_mobile/features/seller_verification/view/seller_verification_screen.dart';
import 'package:agrobenta_mobile/features/terms_and_policies/view/terms_and_policies_screen.dart';
import 'package:agrobenta_mobile/widgets/trinidad_location_selector.dart';
import 'package:agrobenta_mobile/repositories/profile_repository.dart';
import 'package:agrobenta_mobile/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/auth_app_harness.dart';
import '../../support/auth_fakes.dart';
import '../../support/seller_verification_app_harness.dart';
import '../../support/trinidad_location_fakes.dart';

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
    String? location,
    Future<http.Response> Function(RecordedRequest request)? profileHandler,
  }) async {
    final Map<String, dynamic> currentUser = userJson(
      sellerCapability: sellerCapability,
      location: location,
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
          httpClient: MockClient((http.Request request) async {
            final RecordedRequest entry = RecordedRequest(request);
            if (profileHandler != null) return profileHandler(entry);
            return http.Response(
              jsonEncode(successEnvelope(data: currentUser)),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }),
        ),
      ),
    );
    final ProfileController profileController = ProfileController(
      profileRepository,
    );
    addTearDown(profileController.dispose);

    tokenStore.token = 'stored-token';
    await authController.restoreSession();
    await profileController.load();
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      AuthScope(
        controller: authController,
        child: AccountModeScope(
          controller: accountModeController,
          child: NeverSubmittedVerificationScope(
            child: TrinidadLocationTestScope(
              tokenStore: tokenStore,
              child: ProfileScope(
                repository: profileRepository,
                controller: profileController,
                child: const MaterialApp(home: ProfileScreen()),
              ),
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

  Future<void> tapAddress(WidgetTester tester) async {
    final Finder target = find.text('Address');
    await tester.ensureVisible(target);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(target);
    await settleAuth(tester, frames: 12);
  }

  bool isDisabled(WidgetTester tester, String label) =>
      tester.widget<ListTile>(find.widgetWithText(ListTile, label)).onTap ==
      null;

  testWidgets('renders the caller, address, account mode and settings', (
    WidgetTester tester,
  ) async {
    const String savedAddress = 'Purok 3, Barangay Banlasan, Trinidad, Bohol';
    await pumpProfile(
      tester,
      location: savedAddress,
      handler: (_) async =>
          http.Response(jsonEncode(successEnvelope(data: userJson())), 200),
    );

    // Identity comes from the API payload, never a hardcoded sample.
    expect(find.text('Ana Reyes'), findsOneWidget);
    expect(find.text('ana@example.test'), findsOneWidget);
    expect(find.text('Address'), findsOneWidget);
    expect(find.text(savedAddress), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Address'), findsNothing);
    expect(
      find.ancestor(of: find.text('Address'), matching: find.byType(Card)),
      findsOneWidget,
    );

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
    expect(isDisabled(tester, 'Notification Settings'), isTrue);

    // Help and Terms have destinations; notification preferences remain inert.
    expect(isDisabled(tester, 'Help and Support'), isFalse);
    expect(isDisabled(tester, 'Terms and Policies'), isFalse);
    expect(isDisabled(tester, 'Log Out'), isFalse);
  });

  testWidgets('Help and Support opens Help Center and returns to Profile', (
    WidgetTester tester,
  ) async {
    await pumpProfile(
      tester,
      handler: (_) async =>
          http.Response(jsonEncode(successEnvelope(data: userJson())), 200),
    );

    expect(find.text('Help and Support'), findsOneWidget);
    await tapAction(tester, 'Help and Support');

    expect(find.byType(HelpCenterScreen), findsOneWidget);
    expect(find.text('Help & Support'), findsOneWidget);
    await tester.pageBack();
    await settleAuth(tester, frames: 12);

    expect(find.byType(HelpCenterScreen), findsNothing);
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.text('Help and Support'), findsOneWidget);
  });

  testWidgets('rapid Help and Support taps push only one Help Center', (
    WidgetTester tester,
  ) async {
    await pumpProfile(
      tester,
      handler: (_) async =>
          http.Response(jsonEncode(successEnvelope(data: userJson())), 200),
    );

    final Finder helpRow = find.widgetWithText(ListTile, 'Help and Support');
    final VoidCallback? onTap = tester.widget<ListTile>(helpRow).onTap;
    expect(onTap, isNotNull);
    onTap!();
    onTap();
    await settleAuth(tester, frames: 12);

    expect(find.byType(HelpCenterScreen), findsOneWidget);
  });

  testWidgets(
    'Terms and Policies opens unavailable-content screen and returns to Profile',
    (WidgetTester tester) async {
      await pumpProfile(
        tester,
        handler: (_) async =>
            http.Response(jsonEncode(successEnvelope(data: userJson())), 200),
      );

      expect(find.text('Terms and Policies'), findsOneWidget);
      await tapAction(tester, 'Terms and Policies');

      expect(find.byType(TermsAndPoliciesScreen), findsOneWidget);
      expect(find.text('Terms & Policies'), findsOneWidget);
      expect(find.text('Terms and Conditions'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(
        find.textContaining('Approved legal content is not available yet.'),
        findsOneWidget,
      );

      await tester.pageBack();
      await settleAuth(tester, frames: 12);

      expect(find.byType(TermsAndPoliciesScreen), findsNothing);
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.text('Terms and Policies'), findsOneWidget);
    },
  );

  testWidgets(
    'rapid Terms and Policies taps push only one availability screen',
    (WidgetTester tester) async {
      await pumpProfile(
        tester,
        handler: (_) async =>
            http.Response(jsonEncode(successEnvelope(data: userJson())), 200),
      );

      final Finder termsRow = find.widgetWithText(
        ListTile,
        'Terms and Policies',
      );
      final VoidCallback? onTap = tester.widget<ListTile>(termsRow).onTap;
      expect(onTap, isNotNull);
      onTap!();
      onTap();
      await settleAuth(tester, frames: 12);

      expect(find.byType(TermsAndPoliciesScreen), findsOneWidget);
    },
  );

  testWidgets('address editor saves through the existing profile update', (
    WidgetTester tester,
  ) async {
    const String initialAddress = 'Purok 3, Barangay Banlasan, Trinidad, Bohol';
    const String updatedAddress =
        'Purok 5, Riverside, Barangay San Isidro, Trinidad, Bohol';
    final List<RecordedRequest> profileRequests = <RecordedRequest>[];

    await pumpProfile(
      tester,
      location: initialAddress,
      handler: (_) async =>
          http.Response(jsonEncode(successEnvelope(data: userJson())), 200),
      profileHandler: (RecordedRequest request) async {
        profileRequests.add(request);
        if (request.method == 'PUT' && request.apiPath.endsWith('/profile')) {
          return http.Response(
            jsonEncode(
              successEnvelope(
                data: userJson(location: request.body['location']),
              ),
            ),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode(successEnvelope(data: userJson(location: initialAddress))),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      },
    );

    await tapAddress(tester);
    expect(find.byType(TrinidadLocationSelector), findsOneWidget);

    await tester.tap(find.byKey(trinidadBarangayFieldKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(trinidadBarangaySearchFieldKey), 'san');
    await tester.pumpAndSettle();
    expect(find.text('4 barangays found'), findsOneWidget);
    expect(find.text('San Isidro'), findsOneWidget);
    expect(find.text('San Vicente'), findsOneWidget);
    expect(find.text('Santo Tomas'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(trinidadBarangayResultsKey),
        matching: find.text('Banlasan'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('San Isidro').last);
    await tester.pumpAndSettle();

    final Finder streetField = find.widgetWithText(
      TextFormField,
      'Street / Purok (optional)',
    );
    await tester.ensureVisible(streetField);
    await tester.enterText(streetField, 'Purok 5, Riverside');
    final Finder saveAddressFinder = find.widgetWithText(
      FilledButton,
      'Save address',
    );
    await tester.ensureVisible(saveAddressFinder);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(saveAddressFinder).onPressed, isNotNull);
    await tester.tap(saveAddressFinder);
    await tester.pumpAndSettle();

    final RecordedRequest update = profileRequests.singleWhere(
      (RecordedRequest request) => request.method == 'PUT',
    );
    expect(update.apiPath, '/profile');
    expect(update.body, <String, dynamic>{'location': updatedAddress});
    expect(find.text(updatedAddress), findsOneWidget);
    expect(find.text('Address'), findsOneWidget);
    expect(find.byType(TrinidadLocationSelector), findsNothing);
  });

  testWidgets('canceling address edits does not persist changes', (
    WidgetTester tester,
  ) async {
    const String savedAddress = 'Purok 3, Barangay Banlasan, Trinidad, Bohol';
    final List<RecordedRequest> profileRequests = <RecordedRequest>[];

    await pumpProfile(
      tester,
      location: savedAddress,
      handler: (_) async =>
          http.Response(jsonEncode(successEnvelope(data: userJson())), 200),
      profileHandler: (RecordedRequest request) async {
        profileRequests.add(request);
        return http.Response(
          jsonEncode(successEnvelope(data: userJson(location: savedAddress))),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      },
    );

    await tapAddress(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Street / Purok (optional)'),
      'Unsaved Purok',
    );
    await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(
      profileRequests.where((request) => request.method == 'PUT'),
      isEmpty,
    );
    expect(find.text(savedAddress), findsOneWidget);
    expect(find.text('Unsaved Purok'), findsNothing);
  });

  testWidgets('an empty address has a clear state', (
    WidgetTester tester,
  ) async {
    await pumpProfile(
      tester,
      handler: (_) async =>
          http.Response(jsonEncode(successEnvelope(data: userJson())), 200),
    );
    expect(find.text('Not provided'), findsOneWidget);
    expect(find.text('Tap to add your delivery address'), findsOneWidget);
    await tapAddress(tester);
    expect(find.byType(TrinidadLocationSelector), findsOneWidget);
  });

  testWidgets('long addresses wrap on a narrow phone surface', (
    WidgetTester tester,
  ) async {
    final Size originalSize = tester.view.physicalSize;
    final double originalDpr = tester.view.devicePixelRatio;
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.physicalSize = originalSize;
      tester.view.devicePixelRatio = originalDpr;
    });

    final String street = List<String>.filled(8, 'Riverside').join(' ');
    final String longAddress =
        'Purok $street, Barangay Banlasan, Trinidad, Bohol';
    await pumpProfile(
      tester,
      location: longAddress,
      handler: (_) async =>
          http.Response(jsonEncode(successEnvelope(data: userJson())), 200),
    );
    await tester.ensureVisible(find.text(longAddress));
    await tester.pumpAndSettle();

    expect(find.text(longAddress), findsOneWidget);
    expect(tester.widget<Text>(find.text(longAddress)).softWrap, isTrue);
    expect(tester.takeException(), isNull);
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
      handler: (_) async =>
          http.Response(jsonEncode(successEnvelope(data: userJson())), 200),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await settleAuth(tester, frames: 12);
    expect(find.byType(EditProfileScreen), findsOneWidget);
    expect(find.byType(TrinidadLocationSelector), findsNothing);

    Navigator.of(tester.element(find.byType(EditProfileScreen))).pop();
    await settleAuth(tester, frames: 12);

    await tapAction(tester, 'Personal Information');
    expect(find.byType(EditProfileScreen), findsOneWidget);
    expect(find.byType(TrinidadLocationSelector), findsNothing);
  });

  testWidgets('Change Password opens the existing password form', (
    WidgetTester tester,
  ) async {
    await pumpProfile(
      tester,
      handler: (_) async =>
          http.Response(jsonEncode(successEnvelope(data: userJson())), 200),
    );

    await tapAction(tester, 'Change Password');
    expect(find.byType(ChangePasswordScreen), findsOneWidget);
  });

  testWidgets('Become a Seller opens the existing verification flow', (
    WidgetTester tester,
  ) async {
    await pumpProfile(
      tester,
      handler: (_) async =>
          http.Response(jsonEncode(successEnvelope(data: userJson())), 200),
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

  testWidgets(
    'edit profile prompts for current password when email changes and sends it',
    (WidgetTester tester) async {
      final List<RecordedRequest> requests = <RecordedRequest>[];
      final ProfileRepository profileRepository = ProfileRepository(
        ProfileService(
          ApiClient(
            tokenStorage: tokenStore,
            httpClient: MockClient((http.Request request) async {
              if (request.method == 'GET' &&
                  request.url.path.endsWith('/profile')) {
                return http.Response(
                  jsonEncode(successEnvelope(data: userJson())),
                  200,
                  headers: <String, String>{'content-type': 'application/json'},
                );
              }
              if (request.method == 'PUT' &&
                  request.url.path.endsWith('/profile')) {
                requests.add(RecordedRequest(request));
                return http.Response(
                  jsonEncode(
                    successEnvelope(data: userJson(email: 'new@example.test')),
                  ),
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
      final ProfileController profileController = ProfileController(
        profileRepository,
      );
      addTearDown(profileController.dispose);

      final AuthController authController = AuthController(
        buildAuthRepository(
          tokenStore,
          (_) async =>
              http.Response(jsonEncode(successEnvelope(data: userJson())), 200),
          recorded: recorded,
        ),
      );
      addTearDown(authController.dispose);
      final AccountModeController accountModeController = AccountModeController(
        authController,
      );
      addTearDown(accountModeController.dispose);

      tokenStore.token = 'stored-token';
      await authController.restoreSession();
      await profileController.load();
      await tester.pumpAndSettle();

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
      await profileController.load();
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email address'),
        'new@example.test',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Save changes'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();

      expect(find.text('Confirm your password'), findsOneWidget);

      // Cancel prevents submission
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        requests
            .where((r) => r.method == 'PUT' && r.apiPath == '/profile')
            .isEmpty,
        isTrue,
      );

      // Try again and confirm
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Save changes'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find
                .widgetWithText(AlertDialog, 'Confirm your password')
                .first
                .evaluate()
                .isEmpty
            ? find.byType(TextField).last
            : find
                  .descendant(
                    of: find.byType(AlertDialog),
                    matching: find.byType(TextField),
                  )
                  .first,
        'password123',
      );
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      final RecordedRequest putReq = requests.firstWhere(
        (r) => r.method == 'PUT' && r.apiPath == '/profile',
      );
      final Map<String, dynamic> body = putReq.body;
      expect(body['email'], 'new@example.test');
      expect(body['current_password'], 'password123');
    },
  );

  testWidgets('editing personal information preserves the saved address', (
    WidgetTester tester,
  ) async {
    const String savedAddress = 'Purok 4, Barangay Banlasan, Trinidad, Bohol';
    final List<RecordedRequest> requests = <RecordedRequest>[];
    final ProfileRepository profileRepository = ProfileRepository(
      ProfileService(
        ApiClient(
          tokenStorage: tokenStore,
          httpClient: MockClient((http.Request request) async {
            if (request.method == 'GET' &&
                request.url.path.endsWith('/profile')) {
              return http.Response(
                jsonEncode(
                  successEnvelope(data: userJson(location: savedAddress)),
                ),
                200,
                headers: <String, String>{'content-type': 'application/json'},
              );
            }
            if (request.method == 'PUT' &&
                request.url.path.endsWith('/profile')) {
              requests.add(RecordedRequest(request));
              return http.Response(
                jsonEncode(
                  successEnvelope(
                    data: userJson(name: 'New Name', location: savedAddress),
                  ),
                ),
                200,
                headers: <String, String>{'content-type': 'application/json'},
              );
            }
            return http.Response(
              jsonEncode(
                successEnvelope(data: userJson(location: savedAddress)),
              ),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }),
        ),
      ),
    );
    final ProfileController profileController = ProfileController(
      profileRepository,
    );
    addTearDown(profileController.dispose);

    final AuthController authController = AuthController(
      buildAuthRepository(
        tokenStore,
        (_) async => http.Response(
          jsonEncode(successEnvelope(data: userJson(location: savedAddress))),
          200,
        ),
        recorded: recorded,
      ),
    );
    addTearDown(authController.dispose);
    final AccountModeController accountModeController = AccountModeController(
      authController,
    );
    addTearDown(accountModeController.dispose);

    tokenStore.token = 'stored-token';
    await authController.restoreSession();
    await profileController.load();
    await tester.pumpAndSettle();

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
    await profileController.load();
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Full name'),
      'New Name',
    );
    final Finder saveBtn = find.widgetWithText(FilledButton, 'Save changes');
    await tester.ensureVisible(saveBtn);
    await tester.pumpAndSettle();
    await tester.tap(saveBtn, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Confirm your password'), findsNothing);
    expect(requests.where((r) => r.method == 'PUT').isNotEmpty, isTrue);
    final RecordedRequest putReq = requests.firstWhere(
      (r) => r.method == 'PUT',
    );
    final Map<String, dynamic> body = putReq.body;
    expect(body.containsKey('current_password'), isFalse);
    expect(body.containsKey('location'), isFalse);
    expect(profileController.state.user?.location, savedAddress);
  });

  testWidgets(
    'edit profile displays server current_password validation error',
    (WidgetTester tester) async {
      final ProfileRepository profileRepository = ProfileRepository(
        ProfileService(
          ApiClient(
            tokenStorage: tokenStore,
            httpClient: MockClient((http.Request request) async {
              if (request.method == 'GET' &&
                  request.url.path.endsWith('/profile')) {
                return http.Response(
                  jsonEncode(successEnvelope(data: userJson())),
                  200,
                  headers: <String, String>{'content-type': 'application/json'},
                );
              }
              if (request.method == 'PUT' &&
                  request.url.path.endsWith('/profile')) {
                return http.Response(
                  jsonEncode(<String, dynamic>{
                    'success': false,
                    'message': 'The given data was invalid.',
                    'errors': <String, dynamic>{
                      'current_password': <String>[
                        'The current password is incorrect.',
                      ],
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
      final ProfileController profileController = ProfileController(
        profileRepository,
      );
      addTearDown(profileController.dispose);

      final AuthController authController = AuthController(
        buildAuthRepository(
          tokenStore,
          (_) async =>
              http.Response(jsonEncode(successEnvelope(data: userJson())), 200),
          recorded: recorded,
        ),
      );
      addTearDown(authController.dispose);
      final AccountModeController accountModeController = AccountModeController(
        authController,
      );
      addTearDown(accountModeController.dispose);

      tokenStore.token = 'stored-token';
      await authController.restoreSession();
      await profileController.load();
      await tester.pumpAndSettle();

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
      await profileController.load();
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email address'),
        'new@example.test',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Save changes'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'wrong');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(find.text('The current password is incorrect.'), findsOneWidget);
      expect(find.text('Confirm your password'), findsOneWidget);
    },
  );

  testWidgets(
    'edit profile retries on multiple incorrect current passwords until success',
    (WidgetTester tester) async {
      final List<RecordedRequest> requests = <RecordedRequest>[];
      int putCount = 0;
      final ProfileRepository profileRepository = ProfileRepository(
        ProfileService(
          ApiClient(
            tokenStorage: tokenStore,
            httpClient: MockClient((http.Request request) async {
              if (request.method == 'GET' &&
                  request.url.path.endsWith('/profile')) {
                return http.Response(
                  jsonEncode(successEnvelope(data: userJson())),
                  200,
                  headers: <String, String>{'content-type': 'application/json'},
                );
              }
              if (request.method == 'PUT' &&
                  request.url.path.endsWith('/profile')) {
                putCount++;
                requests.add(RecordedRequest(request));
                if (putCount == 1) {
                  return http.Response(
                    jsonEncode(<String, dynamic>{
                      'success': false,
                      'message': 'The given data was invalid.',
                      'errors': <String, dynamic>{
                        'current_password': <String>[
                          'The current password is incorrect.',
                        ],
                      },
                    }),
                    422,
                    headers: <String, String>{
                      'content-type': 'application/json',
                    },
                  );
                } else if (putCount == 2) {
                  return http.Response(
                    jsonEncode(<String, dynamic>{
                      'success': false,
                      'message': 'The given data was invalid.',
                      'errors': <String, dynamic>{
                        'current_password': <String>[
                          'The current password is invalid.',
                        ],
                      },
                    }),
                    422,
                    headers: <String, String>{
                      'content-type': 'application/json',
                    },
                  );
                } else {
                  return http.Response(
                    jsonEncode(
                      successEnvelope(
                        data: userJson(email: 'new@example.test'),
                      ),
                    ),
                    200,
                    headers: <String, String>{
                      'content-type': 'application/json',
                    },
                  );
                }
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
      final ProfileController profileController = ProfileController(
        profileRepository,
      );
      addTearDown(profileController.dispose);

      final AuthController authController = AuthController(
        buildAuthRepository(
          tokenStore,
          (_) async =>
              http.Response(jsonEncode(successEnvelope(data: userJson())), 200),
          recorded: recorded,
        ),
      );
      addTearDown(authController.dispose);
      final AccountModeController accountModeController = AccountModeController(
        authController,
      );
      addTearDown(accountModeController.dispose);

      tokenStore.token = 'stored-token';
      await authController.restoreSession();
      await profileController.load();
      await tester.pumpAndSettle();

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
      await profileController.load();
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email address'),
        'new@example.test',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Save changes'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Save changes'),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('Confirm your password'), findsOneWidget);
      expect(find.text('The current password is incorrect.'), findsNothing);

      await tester.enterText(find.byType(TextField).last, 'wrong1');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(find.text('The current password is incorrect.'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'wrong2');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(find.text('The current password is invalid.'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'correct');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(requests.length, 3);
      expect(requests[0].body['current_password'], 'wrong1');
      expect(requests[1].body['current_password'], 'wrong2');
      expect(requests[2].body['current_password'], 'correct');
    },
  );
}
