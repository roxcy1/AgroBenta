import 'dart:convert';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/account_mode/state/account_mode.dart';
import 'package:agrobenta_mobile/features/account_mode/state/account_mode_controller.dart';
import 'package:agrobenta_mobile/features/account_mode/state/account_mode_scope.dart';
import 'package:agrobenta_mobile/features/account_mode/view/account_mode_shell.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_controller.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_scope.dart';
import 'package:agrobenta_mobile/features/marketplace/state/marketplace_controller.dart';
import 'package:agrobenta_mobile/features/marketplace/state/marketplace_scope.dart';
import 'package:agrobenta_mobile/features/messaging/state/conversations_controller.dart';
import 'package:agrobenta_mobile/features/messaging/state/messaging_scope.dart';
import 'package:agrobenta_mobile/features/notifications/state/notifications_controller.dart';
import 'package:agrobenta_mobile/features/notifications/state/notifications_scope.dart';
import 'package:agrobenta_mobile/features/profile/state/profile_controller.dart';
import 'package:agrobenta_mobile/features/profile/state/profile_scope.dart';
import 'package:agrobenta_mobile/features/seller_listings/state/seller_listing_controller.dart';
import 'package:agrobenta_mobile/features/seller_listings/state/seller_listing_scope.dart';
import 'package:agrobenta_mobile/features/transactions/state/transaction_scope.dart';
import 'package:agrobenta_mobile/repositories/profile_repository.dart';
import 'package:agrobenta_mobile/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'auth_fakes.dart';
import 'marketplace_fakes.dart';
import 'messaging_fakes.dart';
import 'notification_fakes.dart';
import 'seller_listing_fakes.dart';
import 'seller_verification_app_harness.dart';
import 'transaction_fakes.dart';

/// Pumps [AccountModeShell] with the scopes `main.dart` installs above
/// `MaterialApp`, over one recorded mock transport.
///
/// The tests exercise the real shell switch rather than mounting BuyerShell or
/// SellerShell directly. Seller Mode eagerly builds My Listings, Messages,
/// Transactions and Profile, so every scope those screens read is installed and
/// every initial request they make is answered.
class AccountModeShellHarness {
  const AccountModeShellHarness._(
    this.authController,
    this.accountModeController,
    this.recorded,
  );

  final AuthController authController;
  final AccountModeController accountModeController;
  final List<RecordedRequest> recorded;

  static Future<AccountModeShellHarness> pump(
    WidgetTester tester, {
    String sellerCapability = 'seller',
  }) async {
    final FakeTokenStore tokenStore = FakeTokenStore('stored-token');
    final List<RecordedRequest> recorded = <RecordedRequest>[];

    Map<String, dynamic> currentUser() =>
        userJson(sellerCapability: sellerCapability);

    Future<http.Response> transport(RecordedRequest request) async {
      switch (request.apiPath) {
        case '/auth/me':
          return http.Response(
            jsonEncode(successEnvelope(data: currentUser())),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        case '/profile':
          return http.Response(
            jsonEncode(successEnvelope(data: currentUser())),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        case '/transactions':
          final String role = request.query['role'] ?? 'buyer';
          return transactionListResponse(
            transactions: <Map<String, dynamic>>[
              transactionJson(
                role: role,
                counterparty: role == 'seller'
                    ? transactionCounterpartyJson(
                        name: 'Ben Cruz',
                        email: 'ben@example.test',
                      )
                    : null,
              ),
            ],
          );
        case '/conversations':
          return conversationsResponse();
        case '/notifications/unread-count':
          return unreadCountResponse();
        case '/notifications':
          return notificationsPageResponse();
        case '/seller/listings':
          return sellerListingListResponse(
            listings: <Map<String, dynamic>>[],
            total: 0,
          );
        case '/listings':
          return marketplaceListResponse(
            listings: <Map<String, dynamic>>[],
            total: 0,
          );
        default:
          return http.Response(
            jsonEncode(<String, String>{'message': 'Not found.'}),
            404,
            headers: <String, String>{'content-type': 'application/json'},
          );
      }
    }

    final AuthController authController = AuthController(
      buildAuthRepository(tokenStore, transport, recorded: recorded),
    );
    addTearDown(authController.dispose);

    final AccountModeController accountModeController = AccountModeController(
      authController,
    );
    addTearDown(accountModeController.dispose);

    final marketplaceRepository = buildMarketplaceRepository(
      tokenStore,
      transport,
      recorded: recorded,
    );
    final MarketplaceController marketplaceController = MarketplaceController(
      marketplaceRepository,
    );
    addTearDown(marketplaceController.dispose);

    final ProfileRepository profileRepository = ProfileRepository(
      ProfileService(
        ApiClient(
          tokenStorage: tokenStore,
          httpClient: _mockClient(transport, recorded),
        ),
      ),
    );
    final ProfileController profileController = ProfileController(
      profileRepository,
    );
    addTearDown(profileController.dispose);

    final transactionRepository = buildTransactionRepository(
      tokenStore,
      transport,
      recorded: recorded,
    );
    final messagingRepository = buildMessagingRepository(
      tokenStore,
      transport,
      recorded: recorded,
    );
    final ConversationsController conversationsController =
        ConversationsController(messagingRepository);
    addTearDown(conversationsController.dispose);

    final notificationRepository = buildNotificationRepository(
      tokenStore,
      transport,
      recorded: recorded,
    );
    final NotificationsController notificationsController =
        NotificationsController(notificationRepository);
    addTearDown(notificationsController.dispose);

    final sellerListingRepository = buildSellerListingRepository(
      tokenStore,
      transport,
      recorded: recorded,
    );
    final SellerListingController sellerListingController =
        SellerListingController(sellerListingRepository);
    addTearDown(sellerListingController.dispose);

    await authController.restoreSession();

    await tester.pumpWidget(
      AuthScope(
        controller: authController,
        child: AccountModeScope(
          controller: accountModeController,
          child: MarketplaceScope(
            repository: marketplaceRepository,
            controller: marketplaceController,
            child: SellerListingScope(
              repository: sellerListingRepository,
              controller: sellerListingController,
              child: ProfileScope(
                repository: profileRepository,
                controller: profileController,
                child: TransactionScope(
                  repository: transactionRepository,
                  child: MessagingScope(
                    repository: messagingRepository,
                    conversationsController: conversationsController,
                    child: NotificationsScope(
                      repository: notificationRepository,
                      controller: notificationsController,
                      child: NeverSubmittedVerificationScope(
                        child: MaterialApp(
                          theme: AppTheme.light(),
                          home: const AccountModeShell(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settleAccountModeShell(tester);

    return AccountModeShellHarness._(
      authController,
      accountModeController,
      recorded,
    );
  }

  void select(AccountMode mode) => accountModeController.select(mode);
}

MockClient _mockClient(
  Future<http.Response> Function(RecordedRequest request) handler,
  List<RecordedRequest> recorded,
) {
  return MockClient((http.Request request) async {
    final RecordedRequest entry = RecordedRequest(request);
    recorded.add(entry);
    return handler(entry);
  });
}

/// A bounded pump: a spinner keeps `pumpAndSettle` from returning.
Future<void> settleAccountModeShell(
  WidgetTester tester, {
  int frames = 16,
}) async {
  for (int frame = 0; frame < frames; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
