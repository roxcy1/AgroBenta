import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/network/api_client.dart';
import 'core/storage/token_store.dart';
import 'core/storage/token_storage.dart';
import 'core/theme/app_theme.dart';
import 'features/account_mode/state/account_mode_controller.dart';
import 'features/account_mode/state/account_mode_scope.dart';
import 'features/account_mode/view/account_mode_shell.dart';
import 'features/auth/state/auth_controller.dart';
import 'features/auth/state/auth_scope.dart';
import 'features/auth/view/auth_gate.dart';
import 'features/inquiries/state/inquiry_scope.dart';
import 'features/marketplace/state/marketplace_controller.dart';
import 'features/marketplace/state/marketplace_scope.dart';
import 'features/messaging/state/conversations_controller.dart';
import 'features/messaging/state/messaging_scope.dart';
import 'features/profile/state/profile_controller.dart';
import 'features/profile/state/profile_scope.dart';
import 'features/seller_listings/state/seller_listing_controller.dart';
import 'features/seller_listings/state/seller_listing_scope.dart';
import 'features/seller_verification/state/seller_verification_controller.dart';
import 'features/seller_verification/state/seller_verification_scope.dart';
import 'features/transactions/state/transaction_scope.dart';
import 'repositories/auth_repository.dart';
import 'repositories/inquiry_repository.dart';
import 'repositories/marketplace_repository.dart';
import 'repositories/messaging_repository.dart';
import 'repositories/profile_repository.dart';
import 'repositories/seller_listing_repository.dart';
import 'repositories/seller_verification_repository.dart';
import 'repositories/transaction_repository.dart';
import 'services/auth_service.dart';
import 'services/inquiry_service.dart';
import 'services/marketplace_service.dart';
import 'services/messaging_service.dart';
import 'services/profile_service.dart';
import 'services/seller_listing_service.dart';
import 'services/seller_verification_service.dart';
import 'services/transaction_service.dart';
import 'features/notifications/state/notifications_controller.dart';
import 'features/notifications/state/notifications_scope.dart';
import 'repositories/notification_repository.dart';
import 'services/notification_service.dart';

/// AgroBenta mobile client — application entry point.
///
/// The composition root, and the only place long-lived dependencies are
/// constructed. `TokenStorage` and `ApiClient` are shared, so they are created
/// once and disposed once; everything above them is built from those two.
///
/// See `mobile/AGENTS.md` for the development rules, `mobile/DESIGN.md` for the
/// visual rules, and the API gap register for what the backend does not expose
/// yet.
Future<void> main() async {
  // `intl` ships date symbols for `en_US` only; every other locale must be
  // initialised explicitly or `DateFormat(..., 'en_PH')` throws a
  // `LocaleDataException` the first time a date is rendered. On a device that
  // is the first listing a buyer opens, so it has to happen before the first
  // frame — there is no safe lazy point.
  await initializeDateFormatting('en_PH');

  runApp(const AgroBentaApp());
}

class AgroBentaApp extends StatefulWidget {
  const AgroBentaApp({this.tokenStore, super.key});

  /// Overrides the secure token store.
  ///
  /// Production leaves this null so the platform keystore is used. It exists as
  /// a seam for tests: `flutter_secure_storage` goes through a platform channel
  /// that does not exist in a unit test, so an app-level test injects a fake
  /// instead of standing up the Android Keystore.
  final TokenStore? tokenStore;

  @override
  State<AgroBentaApp> createState() => _AgroBentaAppState();
}

class _AgroBentaAppState extends State<AgroBentaApp> {
  late final TokenStore _tokenStore;
  late final ApiClient _apiClient;
  late final AuthService _authService;
  late final AuthRepository _authRepository;
  late final AuthController _authController;
  late final AccountModeController _accountModeController;
  late final MarketplaceService _marketplaceService;
  late final MarketplaceRepository _marketplaceRepository;
  late final MarketplaceController _marketplaceController;
  late final SellerVerificationService _sellerVerificationService;
  late final SellerVerificationRepository _sellerVerificationRepository;
  late final SellerVerificationController _sellerVerificationController;
  late final SellerListingService _sellerListingService;
  late final SellerListingRepository _sellerListingRepository;
  late final SellerListingController _sellerListingController;
  late final ProfileService _profileService;
  late final ProfileRepository _profileRepository;
  late final ProfileController _profileController;
  late final TransactionService _transactionService;
  late final TransactionRepository _transactionRepository;
  late final MessagingService _messagingService;
  late final MessagingRepository _messagingRepository;
  late final ConversationsController _conversationsController;
  late final NotificationService _notificationService;
  late final NotificationRepository _notificationRepository;
  late final NotificationsController _notificationsController;
  late final InquiryService _inquiryService;
  late final InquiryRepository _inquiryRepository;

  @override
  void initState() {
    super.initState();

    _tokenStore = widget.tokenStore ?? TokenStorage();
    _apiClient = ApiClient(tokenStorage: _tokenStore);
    _authService = AuthService(_apiClient);
    _authRepository = AuthRepository(_authService, _tokenStore);
    _authController = AuthController(_authRepository);
    _accountModeController = AccountModeController(_authController);

    // Shares the one `ApiClient`, so there is a single place that knows about
    // the base URL, the bearer token and the auth-failure side effects.
    _marketplaceService = MarketplaceService(_apiClient);
    _marketplaceRepository = MarketplaceRepository(_marketplaceService);
    _marketplaceController = MarketplaceController(_marketplaceRepository);

    _sellerVerificationService = SellerVerificationService(_apiClient);
    _sellerVerificationRepository = SellerVerificationRepository(
      _sellerVerificationService,
    );
    _sellerVerificationController = SellerVerificationController(
      _sellerVerificationRepository,
      // Approval moves `seller_capability` on the account, so the session's user
      // is re-read from `/auth/me` when a verification comes back approved. The
      // capability is server-owned: this is the app asking, not deciding.
      onCapabilityMayHaveChanged: _authController.refreshUser,
    );

    // Built for every account, not only for sellers. The scope is unconditional
    // so the widget tree does not change shape when a verification is approved
    // mid-session, and the gate is on the requests themselves: the server answers
    // `403` for a non-seller. Nothing here decides who is allowed to sell.
    _sellerListingService = SellerListingService(_apiClient);
    _sellerListingRepository = SellerListingRepository(_sellerListingService);
    _sellerListingController = SellerListingController(
      _sellerListingRepository,
    );

    // Profile. Session-scoped like the others so the profile loaded once is not
    // re-fetched every time the user taps the Profile tab. Installed above
    // `MaterialApp` so the pushed Edit Profile and Change Password screens can
    // reach it.
    _profileService = ProfileService(_apiClient);
    _profileRepository = ProfileRepository(_profileService);
    _profileController = ProfileController(_profileRepository);

    // Transactions. No session-scoped controller: each tab owns one, because
    // each tab is an independent filtered query. The repository is shared so
    // the scope above `MaterialApp` can serve the pushed detail screen.
    _transactionService = TransactionService(_apiClient);
    _transactionRepository = TransactionRepository(_transactionService);

    // Messaging. The repository is shared and the conversations controller is
    // session-scoped so the buyer shell's unread badge and the Conversations
    // screen read the same state. The chat controller is per-screen and lives
    // inside the chat screen itself.
    _messagingService = MessagingService(_apiClient);
    _messagingRepository = MessagingRepository(_messagingService);
    _conversationsController = ConversationsController(_messagingRepository);

    // Notifications. Session-scoped like the Conversations controller so the
    // bell icon's unread badge on the Home AppBar and the Notifications screen
    // read the same state. The controller does not load on construction —
    // screens trigger `load()` / `refreshUnreadCount()` when they appear, so
    // an account that never opens the bell never pays for a request.
    _notificationService = NotificationService(_apiClient);
    _notificationRepository = NotificationRepository(_notificationService);
    _notificationsController = NotificationsController(_notificationRepository);

    // Inquiries. No session-scoped controller: the inquire screen owns its
    // own (a one-shot form, disposed with its route), so only the repository
    // is shared — through a scope above `MaterialApp`, where the pushed
    // screen can reach it.
    _inquiryService = InquiryService(_apiClient);
    _inquiryRepository = InquiryRepository(_inquiryService);
  }

  @override
  void dispose() {
    // The controllers own no transport of their own, and the client they were
    // built on is closed here — the one place that created it.
    _accountModeController.dispose();
    _authController.dispose();
    _marketplaceController.dispose();
    _sellerVerificationController.dispose();
    _sellerListingController.dispose();
    _profileController.dispose();
    _conversationsController.dispose();
    _notificationsController.dispose();
    _apiClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The scopes are deliberately **above** `MaterialApp`, not inside its
    // `home`. `MaterialApp` builds the `Navigator`, and a route pushed onto it
    // is a *sibling* of the home route inside the overlay — not a descendant of
    // it. Anything provided from inside `home` is therefore invisible to every
    // pushed route, which is exactly where the listing detail screen lives: the
    // scope lookups there would fail and the app would assert the moment a
    // buyer tapped a card.
    return AuthScope(
      controller: _authController,
      child: AccountModeScope(
        controller: _accountModeController,
        child: MarketplaceScope(
          repository: _marketplaceRepository,
          controller: _marketplaceController,
          // Outside `MarketplaceScope` rather than nested inside it: the seller
          // verification screens are pushed from Home, and a scope nested in
          // `home` would be invisible to them for the same reason the outer scopes
          // must sit above `MaterialApp`.
          child: SellerVerificationScope(
            repository: _sellerVerificationRepository,
            controller: _sellerVerificationController,
            // Sibling of the other scopes, not nested inside one of them, for the
            // same reason each of them sits above `MaterialApp`: My Listings and
            // the form are pushed routes and need to reach this from a route
            // pushed by a widget that is a descendant of the shell.
            child: SellerListingScope(
              repository: _sellerListingRepository,
              controller: _sellerListingController,
              // Profile sits as a sibling of the other scopes, above
              // `MaterialApp`, for the same reason each of them does: the
              // profile screens are pushed routes and a scope installed inside
              // `home` would be invisible to them.
              child: ProfileScope(
                repository: _profileRepository,
                controller: _profileController,
                // Transactions sits as a sibling of the other scopes, above
                // `MaterialApp`, for the same reason each of them does: the
                // detail screen is a pushed route.
                child: TransactionScope(
                  repository: _transactionRepository,
                  // Messaging sits as a sibling of the other scopes, above
                  // `MaterialApp`, for the same reason each of them does: the
                  // chat screen is a pushed route and needs to reach the shared
                  // repository and the conversations controller.
                  child: MessagingScope(
                    repository: _messagingRepository,
                    conversationsController: _conversationsController,
                    // Notifications sits as a sibling of the other scopes, above
                    // `MaterialApp`, for the same reason each of them does: the
                    // Notifications screen is a pushed route and the bell icon
                    // in the Home AppBar needs to reach the same controller.
                    child: NotificationsScope(
                      repository: _notificationRepository,
                      controller: _notificationsController,
                      // Inquiries sits as a sibling of the other scopes, above
                      // `MaterialApp`, for the same reason each of them does: the
                      // inquire screen is a pushed route, and only the
                      // repository is shared — the screen builds its own
                      // controller and disposes it with the route.
                      child: InquiryScope(
                        repository: _inquiryRepository,
                        child: MaterialApp(
                          title: 'AgroBenta',
                          debugShowCheckedModeBanner: false,
                          theme: AppTheme.light(),
                          home: AuthGate(
                            authenticatedView: _buildAccountModeShell,
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
      ),
    );
  }

  /// The signed-in destination, kept as a static so the gate is handed a stable
  /// builder rather than a fresh closure on every frame. The shell it returns
  /// follows the Account Mode and re-checks the server-granted capability.
  static Widget _buildAccountModeShell(BuildContext context) =>
      const AccountModeShell();
}
