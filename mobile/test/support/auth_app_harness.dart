import 'dart:convert';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_controller.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_scope.dart';
import 'package:agrobenta_mobile/features/auth/view/auth_gate.dart';
import 'package:agrobenta_mobile/features/home/view/buyer_home_screen.dart';
import 'package:agrobenta_mobile/features/marketplace/state/marketplace_controller.dart';
import 'package:agrobenta_mobile/features/marketplace/state/marketplace_scope.dart';
import 'package:agrobenta_mobile/features/notifications/state/notifications_controller.dart';
import 'package:agrobenta_mobile/features/notifications/state/notifications_scope.dart';
import 'package:agrobenta_mobile/features/profile/view/profile_screen.dart';
import 'package:agrobenta_mobile/features/profile/state/profile_controller.dart';
import 'package:agrobenta_mobile/features/profile/state/profile_scope.dart';
import 'package:agrobenta_mobile/repositories/marketplace_repository.dart';
import 'package:agrobenta_mobile/repositories/notification_repository.dart';
import 'package:agrobenta_mobile/repositories/profile_repository.dart';
import 'package:agrobenta_mobile/services/marketplace_service.dart';
import 'package:agrobenta_mobile/services/notification_service.dart';
import 'package:agrobenta_mobile/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'auth_fakes.dart';
import 'seller_verification_app_harness.dart';

/// The signed-in destination the gate is given in tests. Kept as a function
/// rather than a widget so it matches how `main.dart` supplies it.
///
/// The header's profile action swaps in the profile screen **in place** — the
/// same switch the buyer shell's Profile tab does — rather than pushing a
/// route. A pushed route would outlive a sign-out and sit on top of the
/// sign-in form, which never happens in production: the shell's tabs live
/// inside the destination AuthGate replaces wholesale.
Widget _signedInView(BuildContext context) => const _HomeWithProfileAction();

class _HomeWithProfileAction extends StatefulWidget {
  const _HomeWithProfileAction();

  @override
  State<_HomeWithProfileAction> createState() => _HomeWithProfileActionState();
}

class _HomeWithProfileActionState extends State<_HomeWithProfileAction> {
  bool _showProfile = false;

  @override
  Widget build(BuildContext context) {
    if (_showProfile) {
      return const ProfileScreen();
    }
    return BuyerHomeScreen(
      onOpenProfile: () => setState(() => _showProfile = true),
    );
  }
}

/// Pumps the real app shell — theme, `AuthScope`, `AuthGate` — over a mock
/// transport.
///
/// Nothing here touches the network or the platform keystore: the token store
/// is a fake and the HTTP client is a `MockClient`.
///
/// The Home screen the gate renders reads `MarketplaceScope` and
/// `NotificationsScope` in its `initState` (the shared marketplace controller
/// and the notifications bell), and the profile screen reached from it reads
/// `ProfileScope`, so the harness installs all three — over their own canned
/// transports, because the auth tests are not about those features and their
/// handlers must not be confused with the auth handler under test.
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

    // Canned transports for the scopes Home reads but the auth tests do not
    // exercise: an empty marketplace page and a zero unread count.
    final MarketplaceRepository marketplaceRepository = MarketplaceRepository(
      MarketplaceService(
        ApiClient(
          tokenStorage: tokenStore,
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode(
                successEnvelope(
                  data: <String, dynamic>{
                    'listings': <dynamic>[],
                    'pagination': <String, dynamic>{
                      'current_page': 1,
                      'last_page': 1,
                      'per_page': 15,
                      'total': 0,
                    },
                  },
                ),
              ),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            ),
          ),
        ),
      ),
    );
    final MarketplaceController marketplaceController = MarketplaceController(
      marketplaceRepository,
    );
    addTearDown(marketplaceController.dispose);

    final NotificationRepository notificationRepository = NotificationRepository(
      NotificationService(
        ApiClient(
          tokenStorage: tokenStore,
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode(
                successEnvelope(data: <String, dynamic>{'count': 0}),
              ),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            ),
          ),
        ),
      ),
    );
    final NotificationsController notificationsController =
        NotificationsController(notificationRepository);
    addTearDown(notificationsController.dispose);

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

    await tester.pumpWidget(
      // Scopes **above** `MaterialApp`, as `main.dart` does: the profile
      // screen is a pushed route, and a scope nested inside `home` would be
      // invisible to it. The seller verification scope is answered with
      // "never submitted", and the profile transport with the canned user —
      // neither is what the auth tests are about.
      AuthScope(
        controller: controller,
        child: MarketplaceScope(
          repository: marketplaceRepository,
          controller: marketplaceController,
          child: NotificationsScope(
            repository: notificationRepository,
            controller: notificationsController,
            child: NeverSubmittedVerificationScope(
              child: ProfileScope(
                repository: profileRepository,
                controller: profileController,
                child: MaterialApp(
                  theme: AppTheme.light(),
                  home: const AuthGate(authenticatedView: _signedInView),
                ),
              ),
            ),
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
