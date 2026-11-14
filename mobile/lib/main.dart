import 'dart:async';
import 'dart:ui' show FlutterView;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:http/http.dart' as http;

import 'core/network/api_client.dart';
import 'core/platform/installed_app.dart';
import 'core/push/firebase_push_messaging.dart';
import 'core/push/push_messaging.dart';
import 'core/realtime/realtime_client.dart';
import 'core/realtime/realtime_controller.dart';
import 'core/realtime/realtime_event.dart';
import 'core/realtime/realtime_scope.dart';
import 'core/storage/account_mode_preference_store.dart';
import 'core/storage/token_store.dart';
import 'core/storage/token_storage.dart';
import 'core/theme/app_theme.dart';
import 'features/account_mode/state/account_mode_controller.dart';
import 'features/account_mode/state/account_mode_scope.dart';
import 'features/account_mode/view/account_mode_shell.dart';
import 'features/app_update/state/app_update_scope.dart';
import 'features/auth/state/auth_controller.dart';
import 'features/auth/state/auth_scope.dart';
import 'features/auth/view/auth_gate.dart';
import 'features/inquiries/state/inquiry_scope.dart';
import 'features/livestock_types/state/livestock_types_controller.dart';
import 'features/livestock_types/state/livestock_types_scope.dart';
import 'features/marketplace/state/marketplace_controller.dart';
import 'features/marketplace/state/marketplace_scope.dart';
import 'features/messaging/state/conversations_controller.dart';
import 'features/messaging/state/messaging_scope.dart';
import 'features/offers/state/offer_scope.dart';
import 'features/profile/state/profile_controller.dart';
import 'features/profile/state/profile_scope.dart';
import 'features/seller_dashboard/state/seller_activity_scope.dart';
import 'features/seller_dashboard/state/seller_dashboard_scope.dart';
import 'features/seller_listings/state/seller_listing_controller.dart';
import 'features/seller_listings/state/seller_listing_scope.dart';
import 'features/seller_verification/state/seller_verification_controller.dart';
import 'features/seller_verification/state/seller_verification_scope.dart';
import 'features/transactions/state/transaction_scope.dart';
import 'features/trinidad_location/state/trinidad_location_controller.dart';
import 'features/trinidad_location/state/trinidad_location_scope.dart';
import 'repositories/app_release_repository.dart';
import 'repositories/auth_repository.dart';
import 'repositories/inquiry_repository.dart';
import 'repositories/livestock_type_repository.dart';
import 'repositories/marketplace_repository.dart';
import 'repositories/messaging_repository.dart';
import 'repositories/offer_repository.dart';
import 'repositories/profile_repository.dart';
import 'repositories/seller_activity_repository.dart';
import 'repositories/seller_dashboard_repository.dart';
import 'repositories/seller_listing_repository.dart';
import 'repositories/seller_verification_repository.dart';
import 'repositories/transaction_repository.dart';
import 'repositories/trinidad_location_repository.dart';
import 'services/app_release_service.dart';
import 'services/auth_service.dart';
import 'services/inquiry_service.dart';
import 'services/livestock_type_service.dart';
import 'services/marketplace_service.dart';
import 'services/messaging_service.dart';
import 'services/offer_service.dart';
import 'services/profile_service.dart';
import 'services/seller_activity_service.dart';
import 'services/seller_dashboard_service.dart';
import 'services/seller_listing_service.dart';
import 'services/seller_verification_service.dart';
import 'services/transaction_service.dart';
import 'services/trinidad_location_service.dart';
import 'features/notifications/state/notifications_controller.dart';
import 'features/notifications/state/notifications_scope.dart';
import 'features/notifications/state/push_registration_controller.dart';
import 'features/notifications/view/notifications_screen.dart';
import 'repositories/device_repository.dart';
import 'repositories/notification_repository.dart';
import 'services/device_service.dart';
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
  WidgetsFlutterBinding.ensureInitialized();

  // `intl` ships date symbols for `en_US` only; every other locale must be
  // initialised explicitly or `DateFormat(..., 'en_PH')` throws a
  // `LocaleDataException` the first time a date is rendered. On a device that
  // is the first listing a buyer opens, so it has to happen before the first
  // frame — there is no safe lazy point.
  await initializeDateFormatting('en_PH');

  // Firebase push on Android only; every other platform gets the no-op.
  final PushMessaging pushMessaging =
      FirebasePushMessaging.forCurrentPlatform();

  if (kIsWeb) {
    runWidget(_WebMultiViewRoot(pushMessaging: pushMessaging));
  } else {
    runApp(AgroBentaApp(pushMessaging: pushMessaging));
  }
}

/// Creates one app tree for each Flutter view supplied by the web embedder.
///
/// The embedder can add or remove views after startup. Its view list is
/// refreshed when the platform dispatcher reports metric changes.
class _WebMultiViewRoot extends StatefulWidget {
  const _WebMultiViewRoot({required this.pushMessaging});

  final PushMessaging pushMessaging;

  @override
  State<_WebMultiViewRoot> createState() => _WebMultiViewRootState();
}

class _WebMultiViewRootState extends State<_WebMultiViewRoot>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ViewCollection(
    views: WidgetsBinding.instance.platformDispatcher.views
        .map(
          (FlutterView view) => View(
            key: ValueKey<int>(view.viewId),
            view: view,
            child: AgroBentaApp(pushMessaging: widget.pushMessaging),
          ),
        )
        .toList(growable: false),
  );
}

class AgroBentaApp extends StatefulWidget {
  const AgroBentaApp({
    this.tokenStore,
    this.accountModePreferenceStore,
    this.httpClient,
    this.pushMessaging,
    this.installedApp,
    this.linkOpener,
    super.key,
  });

  /// Overrides how the installed version is read and how the update download
  /// is opened, for tests (both use platform channels). Production leaves
  /// them null.
  final InstalledApp? installedApp;
  final ExternalLinkOpener? linkOpener;

  /// The phone's push notification source.
  ///
  /// Null means no push. Only `main()` passes the Firebase implementation, so
  /// tests, which have no Firebase platform channel, never start it.
  final PushMessaging? pushMessaging;

  /// Overrides the secure token store.
  ///
  /// Production leaves this null so the platform keystore is used. It exists as
  /// a seam for tests: `flutter_secure_storage` goes through a platform channel
  /// that does not exist in a unit test, so an app-level test injects a fake
  /// instead of standing up the Android Keystore.
  final TokenStore? tokenStore;

  /// Overrides per-account mode persistence for tests.
  final AccountModePreferenceStore? accountModePreferenceStore;

  /// Overrides the shared transport for composition-root regression tests.
  final http.Client? httpClient;

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
  late final AccountModePreferenceStore _accountModePreferenceStore;
  late final MarketplaceService _marketplaceService;
  late final MarketplaceRepository _marketplaceRepository;
  late MarketplaceController _marketplaceController;
  late final SellerVerificationService _sellerVerificationService;
  late final SellerVerificationRepository _sellerVerificationRepository;
  late SellerVerificationController _sellerVerificationController;
  late final SellerListingService _sellerListingService;
  late final SellerListingRepository _sellerListingRepository;
  late SellerListingController _sellerListingController;
  late final SellerDashboardService _sellerDashboardService;
  late final SellerDashboardRepository _sellerDashboardRepository;
  late final SellerActivityService _sellerActivityService;
  late final SellerActivityRepository _sellerActivityRepository;
  late final AppReleaseRepository _appReleaseRepository;
  late final ProfileService _profileService;
  late final ProfileRepository _profileRepository;
  late ProfileController _profileController;
  late final TransactionService _transactionService;
  late final TransactionRepository _transactionRepository;
  late final MessagingService _messagingService;
  late final MessagingRepository _messagingRepository;
  late ConversationsController _conversationsController;
  late final NotificationService _notificationService;
  late final NotificationRepository _notificationRepository;
  late NotificationsController _notificationsController;
  late final InquiryService _inquiryService;
  late final InquiryRepository _inquiryRepository;
  late final OfferService _offerService;
  late final OfferRepository _offerRepository;
  late final LivestockTypeService _livestockTypeService;
  late final LivestockTypeRepository _livestockTypeRepository;
  late final LivestockTypesController _livestockTypesController;
  late final TrinidadLocationService _trinidadLocationService;
  late final TrinidadLocationRepository _trinidadLocationRepository;
  late final TrinidadLocationController _trinidadLocationController;
  late final PusherReverbClient _realtimeClient;
  late final RealtimeController _realtimeController;
  StreamSubscription<bool>? _realtimeConnectionSubscription;
  late final PushMessaging _pushMessaging;
  late final PushRegistrationController _pushRegistrationController;
  StreamSubscription<Map<String, String>>? _pushOpenedSubscription;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  /// A push was tapped before a session was restored; open the Notifications
  /// screen once the user is signed in.
  bool _pendingPushOpen = false;
  int? _sessionUserId;
  bool _sessionControllersCreated = false;

  @override
  void initState() {
    super.initState();

    _tokenStore = widget.tokenStore ?? TokenStorage();
    _apiClient = ApiClient(
      tokenStorage: _tokenStore,
      httpClient: widget.httpClient,
      // A 403 may mean seller rights were removed after sign-in, so the account
      // is re-read from the server; the controller then drops Seller Mode.
      onForbidden: () => _accountModeController.recheckSellerCapability(),
    );
    _authService = AuthService(_apiClient);
    _authRepository = AuthRepository(_authService, _tokenStore);
    _authController = AuthController(_authRepository);
    _accountModePreferenceStore =
        widget.accountModePreferenceStore ?? SecureAccountModePreferenceStore();
    _accountModeController = AccountModeController(
      _authController,
      preferenceStore: _accountModePreferenceStore,
    );

    // Shares the one `ApiClient`, so there is a single place that knows about
    // the base URL, the bearer token and the auth-failure side effects.
    _marketplaceService = MarketplaceService(_apiClient);
    _marketplaceRepository = MarketplaceRepository(_marketplaceService);

    _sellerVerificationService = SellerVerificationService(_apiClient);
    _sellerVerificationRepository = SellerVerificationRepository(
      _sellerVerificationService,
    );

    // Built for every account, not only for sellers. The scope is unconditional
    // so the widget tree does not change shape when a verification is approved
    // mid-session, and the gate is on the requests themselves: the server answers
    // `403` for a non-seller. Nothing here decides who is allowed to sell.
    _sellerListingService = SellerListingService(_apiClient);
    _sellerListingRepository = SellerListingRepository(_sellerListingService);

    // The seller dashboard is read-only and per-screen: Seller Home creates
    // its own controller and disposes it with the tab. Only the repository is
    // shared through a scope above `MaterialApp`.
    _sellerDashboardService = SellerDashboardService(_apiClient);
    _sellerDashboardRepository = SellerDashboardRepository(
      _sellerDashboardService,
    );
    _sellerActivityService = SellerActivityService(_apiClient);
    _sellerActivityRepository = SellerActivityRepository(
      _sellerActivityService,
    );

    // App updates: the Profile screen's App Update tile compares this build
    // with the latest published one and opens the download in the browser.
    _appReleaseRepository = AppReleaseRepository(
      AppReleaseService(_apiClient),
      widget.installedApp ?? const PackageInfoInstalledApp(),
      widget.linkOpener ?? const UrlLauncherLinkOpener(),
    );

    // Profile. Session-scoped like the others so the profile loaded once is not
    // re-fetched every time the user taps the Profile tab. Installed above
    // `MaterialApp` so the pushed Edit Profile and Change Password screens can
    // reach it.
    _profileService = ProfileService(_apiClient);
    _profileRepository = ProfileRepository(_profileService);

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

    // Notifications. Session-scoped like the Conversations controller so the
    // bell icon's unread badge on the Home AppBar and the Notifications screen
    // read the same state. The controller does not load on construction —
    // screens trigger `load()` / `refreshUnreadCount()` when they appear, so
    // an account that never opens the bell never pays for a request.
    _notificationService = NotificationService(_apiClient);
    _notificationRepository = NotificationRepository(_notificationService);

    // Inquiries. No session-scoped controller: the inquire screen owns its
    // own (a one-shot form, disposed with its route), so only the repository
    // is shared — through a scope above `MaterialApp`, where the pushed
    // screen can reach it.
    _inquiryService = InquiryService(_apiClient);
    _inquiryRepository = InquiryRepository(_inquiryService);

    // Offers. No session-scoped controller: making an offer is a one-shot form
    // and the chat's offer list is per-thread, so only the repository is
    // shared — through a scope above `MaterialApp`, where both the pushed
    // make-offer screen and every chat route can reach it.
    _offerService = OfferService(_apiClient);
    _offerRepository = OfferRepository(_offerService);
    // The approved livestock-type catalog. Session-scoped so the seller form,
    // marketplace filter and every label read one server-owned list. The
    // signed-in shell warms it; the form and filter can retry it independently.
    _livestockTypeService = LivestockTypeService(_apiClient);
    _livestockTypeRepository = LivestockTypeRepository(_livestockTypeService);
    _livestockTypesController = LivestockTypesController(
      _livestockTypeRepository,
    );
    _trinidadLocationService = TrinidadLocationService(_apiClient);
    _trinidadLocationRepository = TrinidadLocationRepository(
      _trinidadLocationService,
    );
    _trinidadLocationController = TrinidadLocationController(
      _trinidadLocationRepository,
    );

    // Real-time: the WebSocket client is created once; the controller connects
    // and disconnects as the session changes (see _handleAuthSessionChanged).
    // Created before the session controllers because they subscribe to its
    // decoded events themselves.
    _realtimeClient = PusherReverbClient(_tokenStore);
    _realtimeController = RealtimeController(_realtimeClient);

    // These controllers hold responses scoped to the bearer token. Recreate
    // them when the authenticated identity changes so their caches, loading
    // guards, and generations cannot cross account boundaries. Screen-owned
    // controllers are disposed with the authenticated shell itself.
    _createSessionControllers();

    _realtimeConnectionSubscription = _realtimeController.connected.listen(
      _handleRealtimeConnection,
    );

    // Push: registered with the backend for each session (see
    // _handleAuthSessionChanged). A tapped push opens the Notifications screen.
    _pushMessaging = widget.pushMessaging ?? const NoopPushMessaging();
    _pushRegistrationController = PushRegistrationController(
      _pushMessaging,
      DeviceRepository(DeviceService(_apiClient)),
    );
    _pushOpenedSubscription = _pushMessaging.openedNotifications.listen(
      (_) => _handlePushOpened(),
      onError: (Object error) =>
          debugPrint('Opening a push failed: ${error.runtimeType}'),
    );

    _authController.addListener(_handleAuthSessionChanged);
  }

  void _handlePushOpened() {
    if (_sessionUserId == null) {
      _pendingPushOpen = true;
      return;
    }
    _openNotifications();
  }

  void _openNotifications() {
    _pendingPushOpen = false;
    // After the next frame, so the signed-in shell is already in place when
    // the push arrived with the session restore. A frame is requested because
    // a tap on a push changes nothing else on screen that would schedule one.
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        _navigatorKey.currentState?.push(
          MaterialPageRoute<void>(
            builder: (BuildContext context) => const NotificationsScreen(),
          ),
        );
      })
      ..scheduleFrame();
  }

  void _handleAuthSessionChanged() {
    final int? userId = _authController.state.isSignedIn
        ? _authController.state.user?.id
        : null;
    if (userId == _sessionUserId) {
      return;
    }

    // Push follows the session too: the old phone registration ends with the
    // old session, and the new one registers this phone for its user. The
    // controller runs these in order.
    if (_sessionUserId != null) {
      _pushRegistrationController.stop();
    }
    if (userId != null) {
      _pushRegistrationController.start();
    }

    _sessionUserId = userId;
    _createSessionControllers(replaceExisting: true);

    if (userId != null && _pendingPushOpen) {
      _openNotifications();
    }

    // Real-time follows the session: connect the user's private channel, or
    // disconnect when signed out.
    if (userId == null) {
      _realtimeController.stop();
    } else {
      _realtimeController.start(userId);
    }

    if (mounted) {
      setState(() {});
    }
  }

  /// A (re)connection is the point where events may have been missed while the
  /// socket was down. Re-fetch the authoritative state so nothing is lost;
  /// duplicate events from the overlap are harmless because the screens
  /// replace their data from the REST response.
  void _handleRealtimeConnection(bool connected) {
    if (!connected) {
      return;
    }

    _notificationsController.refreshUnreadCount();
    _conversationsController.refresh();
    _sellerVerificationController.load();
    _sellerListingController.refresh();
  }

  void _createSessionControllers({bool replaceExisting = false}) {
    if (replaceExisting && _sessionControllersCreated) {
      _marketplaceController.dispose();
      _sellerVerificationController.dispose();
      _sellerListingController.dispose();
      _profileController.dispose();
      _conversationsController.dispose();
      _notificationsController.dispose();
    }

    // Each session controller subscribes to the decoded events and refreshes
    // only the surface it owns (see `_onRealtimeEvent` in each controller).
    final Stream<RealtimeEvent> realtimeEvents = _realtimeController.events;

    _marketplaceController = MarketplaceController(
      _marketplaceRepository,
      realtimeEvents: realtimeEvents,
    );
    _sellerVerificationController = SellerVerificationController(
      _sellerVerificationRepository,
      realtimeEvents: realtimeEvents,
      // Approval moves `seller_capability` on the account, so the session's user
      // is re-read from `/auth/me` when a verification comes back approved. The
      // capability is server-owned: this is the app asking, not deciding.
      onCapabilityMayHaveChanged: _authController.refreshUser,
    );
    _sellerListingController = SellerListingController(
      _sellerListingRepository,
      realtimeEvents: realtimeEvents,
    );
    _profileController = ProfileController(_profileRepository);
    _conversationsController = ConversationsController(
      _messagingRepository,
      realtimeEvents: realtimeEvents,
    );
    _notificationsController = NotificationsController(
      _notificationRepository,
      realtimeEvents: realtimeEvents,
    );
    _sessionControllersCreated = true;
  }

  @override
  void dispose() {
    // The controllers own no transport of their own, and the client they were
    // built on is closed here — the one place that created it.
    _authController.removeListener(_handleAuthSessionChanged);
    _accountModeController.dispose();
    _authController.dispose();
    _marketplaceController.dispose();
    _sellerVerificationController.dispose();
    _sellerListingController.dispose();
    _profileController.dispose();
    _conversationsController.dispose();
    _notificationsController.dispose();
    _livestockTypesController.dispose();
    _trinidadLocationController.dispose();
    _realtimeConnectionSubscription?.cancel();
    _realtimeController.dispose();
    _pushOpenedSubscription?.cancel();
    _pushRegistrationController.dispose();
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
    return TrinidadLocationScope(
      repository: _trinidadLocationRepository,
      controller: _trinidadLocationController,
      child: LivestockTypesScope(
        repository: _livestockTypeRepository,
        controller: _livestockTypesController,
        child: AuthScope(
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
                            // Offers sit above `MaterialApp` for the same reason:
                            // the make-offer form is pushed from the seller's
                            // inquiry inbox and the offer panel lives inside every
                            // chat route, so both must be able to reach the shared
                            // repository. The controllers are per-screen.
                            child: OfferScope(
                              repository: _offerRepository,
                              // The seller dashboard repository sits above
                              // `MaterialApp` like every other scope. Seller Home
                              // creates its own controller, so only the repository
                              // is long-lived.
                              child: SellerDashboardScope(
                                repository: _sellerDashboardRepository,
                                child: SellerActivityScope(
                                  repository: _sellerActivityRepository,
                                  child: AppUpdateScope(
                                    repository: _appReleaseRepository,
                                    // Real-time sits closest to `MaterialApp` so
                                    // every pushed route can subscribe to the
                                    // session's events without constructor
                                    // threading.
                                    child: RealtimeScope(
                                      controller: _realtimeController,
                                      child: MaterialApp(
                                        navigatorKey: _navigatorKey,
                                        title: 'AgroBenta',
                                        debugShowCheckedModeBanner: false,
                                        theme: AppTheme.light(),
                                        home: AuthGate(
                                          authenticatedView:
                                              _buildAccountModeShell,
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
