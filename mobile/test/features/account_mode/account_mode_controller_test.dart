import 'dart:convert';

import 'package:agrobenta_mobile/features/account_mode/state/account_mode.dart';
import 'package:agrobenta_mobile/features/account_mode/state/account_mode_controller.dart';
import 'package:agrobenta_mobile/features/account_mode/state/account_mode_preference_store.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';

class _MemoryAccountModeStore implements AccountModePreferenceStore {
  final Map<int, String> values = <int, String>{};

  @override
  Future<String?> read(int userId) async => values[userId];

  @override
  Future<void> write(int userId, String mode) async {
    values[userId] = mode;
  }
}

void main() {
  late FakeTokenStore tokenStore;
  late Map<String, dynamic> currentUser;
  late bool fail503;

  setUp(() {
    tokenStore = FakeTokenStore('stored-token');
    currentUser = userJson();
    fail503 = false;
  });

  Future<http.Response> Function(RecordedRequest request) authHandler() {
    return (RecordedRequest request) async {
      if (fail503) {
        return http.Response(jsonEncode(<String, dynamic>{}), 503);
      }
      if (request.apiPath == '/auth/logout') {
        return http.Response(
          jsonEncode(successEnvelope(message: 'Logged out successfully.')),
          200,
        );
      }
      if (request.apiPath == '/auth/login') {
        return http.Response(
          jsonEncode(
            successEnvelope(
              data: authSessionJson(
                token: 'token-${currentUser['id']}',
                user: currentUser,
              ),
            ),
          ),
          200,
        );
      }
      return http.Response(jsonEncode(successEnvelope(data: currentUser)), 200);
    };
  }

  Future<(AuthController, AccountModeController)> restoredSession({
    AccountModePreferenceStore? preferenceStore,
  }) async {
    final AuthController authController = AuthController(
      buildAuthRepository(tokenStore, authHandler()),
    );
    addTearDown(authController.dispose);

    await authController.restoreSession();

    final AccountModeController accountModeController = AccountModeController(
      authController,
      preferenceStore: preferenceStore,
    );
    addTearDown(accountModeController.dispose);

    return (authController, accountModeController);
  }

  Future<void> finishModeRestore(AccountModeController controller) async {
    for (int i = 0; i < 10 && controller.isRestoringPreference; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('starts in Buyer Mode for a verified seller', () async {
    currentUser = userJson(sellerCapability: 'seller');

    final (_, AccountModeController controller) = await restoredSession();

    expect(controller.mode, AccountMode.buyer);
    expect(controller.canUseSellerMode, isTrue);
  });

  test('a buyer cannot select Seller Mode', () async {
    final (_, AccountModeController controller) = await restoredSession();

    controller.select(AccountMode.seller);

    expect(controller.mode, AccountMode.buyer);
    expect(controller.canUseSellerMode, isFalse);
  });

  test('a verified seller can switch between both modes', () async {
    currentUser = userJson(sellerCapability: 'seller');
    final (_, AccountModeController controller) = await restoredSession();

    controller.select(AccountMode.seller);
    expect(controller.mode, AccountMode.seller);

    controller.select(AccountMode.buyer);
    expect(controller.mode, AccountMode.buyer);
  });

  test('signing out clears Seller Mode', () async {
    currentUser = userJson(sellerCapability: 'seller');
    final (AuthController auth, AccountModeController controller) =
        await restoredSession();
    controller.select(AccountMode.seller);

    await auth.signOut();

    expect(controller.mode, AccountMode.buyer);
    expect(controller.canUseSellerMode, isFalse);
  });

  test('losing seller capability clears Seller Mode', () async {
    currentUser = userJson(sellerCapability: 'seller');
    final (AuthController auth, AccountModeController controller) =
        await restoredSession();
    controller.select(AccountMode.seller);

    currentUser = userJson(sellerCapability: 'buyer');
    await auth.refreshUser();

    expect(controller.mode, AccountMode.buyer);
    expect(controller.canUseSellerMode, isFalse);
  });

  test(
    'logging in as a different account clears the previous live mode',
    () async {
      currentUser = userJson(id: 7, sellerCapability: 'seller');
      final (AuthController auth, AccountModeController controller) =
          await restoredSession();
      controller.select(AccountMode.seller);

      await auth.signOut();
      currentUser = userJson(
        id: 8,
        name: 'Ben Cruz',
        email: 'ben@example.test',
        sellerCapability: 'seller',
      );
      await auth.signIn(email: 'ben@example.test', password: 'correct horse');

      expect(controller.mode, AccountMode.buyer);
      expect(controller.canUseSellerMode, isTrue);
    },
  );

  test('requestSellerMode switches a verified seller to Seller Mode', () async {
    currentUser = userJson(sellerCapability: 'seller');
    final (_, AccountModeController controller) = await restoredSession();

    await controller.requestSellerMode();

    expect(controller.mode, AccountMode.seller);
    expect(controller.takeNotice(), isNull);
  });

  test(
    'requestSellerMode refuses a stale seller the server no longer approves',
    () async {
      currentUser = userJson(sellerCapability: 'seller');
      final (_, AccountModeController controller) = await restoredSession();
      expect(controller.canUseSellerMode, isTrue);

      // Seller rights were removed on the server after sign-in.
      currentUser = userJson(sellerCapability: 'buyer');
      await controller.requestSellerMode();

      expect(controller.mode, AccountMode.buyer);
      expect(controller.canUseSellerMode, isFalse);
      expect(controller.takeNotice(), contains('verified sellers'));
    },
  );

  test(
    'requestSellerMode stays in Buyer Mode when the server cannot be reached',
    () async {
      currentUser = userJson(sellerCapability: 'seller');
      final (_, AccountModeController controller) = await restoredSession();

      fail503 = true;
      await controller.requestSellerMode();

      expect(controller.mode, AccountMode.buyer);
      expect(controller.takeNotice(), contains('Could not confirm'));
    },
  );

  test('recheckSellerCapability drops Seller Mode with a notice', () async {
    currentUser = userJson(sellerCapability: 'seller');
    final (_, AccountModeController controller) = await restoredSession();
    controller.select(AccountMode.seller);

    currentUser = userJson(sellerCapability: 'buyer');
    await controller.recheckSellerCapability();

    expect(controller.mode, AccountMode.buyer);
    expect(controller.takeNotice(), contains('no longer a verified seller'));
    expect(controller.takeNotice(), isNull);
  });

  test(
    'gaining seller capability does not switch mode automatically',
    () async {
      final (AuthController auth, AccountModeController controller) =
          await restoredSession();

      currentUser = userJson(sellerCapability: 'seller');
      await auth.refreshUser();

      expect(controller.mode, AccountMode.buyer);
      expect(controller.canUseSellerMode, isTrue);
    },
  );

  test(
    'restores Buyer/Seller Mode independently for each authenticated user',
    () async {
      final _MemoryAccountModeStore preferences = _MemoryAccountModeStore()
        ..values[7] = AccountMode.seller.name
        ..values[8] = AccountMode.buyer.name;
      currentUser = userJson(id: 7, sellerCapability: 'seller');
      final (AuthController auth, AccountModeController controller) =
          await restoredSession(preferenceStore: preferences);
      await finishModeRestore(controller);
      expect(controller.mode, AccountMode.seller);

      await auth.signOut();
      expect(controller.mode, AccountMode.buyer);
      expect(preferences.values[7], AccountMode.seller.name);

      currentUser = userJson(
        id: 8,
        name: 'Ben Cruz',
        email: 'ben@example.test',
        sellerCapability: 'seller',
      );
      await auth.signIn(email: 'ben@example.test', password: 'password');
      await finishModeRestore(controller);
      expect(controller.mode, AccountMode.buyer);
      expect(controller.canUseSellerMode, isTrue);
      expect(preferences.values[7], AccountMode.seller.name);
      expect(preferences.values[8], AccountMode.buyer.name);

      await auth.signOut();
      currentUser = userJson(id: 7, sellerCapability: 'seller');
      await auth.signIn(email: 'ana@example.test', password: 'password');
      await finishModeRestore(controller);
      expect(controller.mode, AccountMode.seller);
    },
  );

  test('persists only an authorized, successfully selected mode', () async {
    final _MemoryAccountModeStore preferences = _MemoryAccountModeStore();
    currentUser = userJson(id: 7, sellerCapability: 'buyer');
    final (AuthController auth, AccountModeController controller) =
        await restoredSession(preferenceStore: preferences);
    await finishModeRestore(controller);

    controller.select(AccountMode.seller);
    expect(controller.mode, AccountMode.buyer);
    expect(preferences.values, isEmpty);

    currentUser = userJson(id: 7, sellerCapability: 'seller');
    await auth.refreshUser();
    await controller.requestSellerMode();
    for (int i = 0; i < 10 && preferences.values[7] == null; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(controller.mode, AccountMode.seller);
    expect(preferences.values[7], AccountMode.seller.name);
  });

  test('a user without a saved preference defaults to Buyer Mode', () async {
    final _MemoryAccountModeStore preferences = _MemoryAccountModeStore();
    currentUser = userJson(id: 7, sellerCapability: 'seller');
    final (_, AccountModeController controller) = await restoredSession(
      preferenceStore: preferences,
    );
    await finishModeRestore(controller);

    expect(controller.mode, AccountMode.buyer);
    expect(preferences.values, isEmpty);
  });

  test(
    'a selected mode is restored by a newly created session controller',
    () async {
      final _MemoryAccountModeStore preferences = _MemoryAccountModeStore();
      currentUser = userJson(id: 7, sellerCapability: 'seller');
      final (AuthController auth, AccountModeController controller) =
          await restoredSession(preferenceStore: preferences);
      await finishModeRestore(controller);

      await controller.requestSellerMode();
      for (int i = 0; i < 10 && preferences.values[7] == null; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(preferences.values[7], AccountMode.seller.name);
      await auth.signOut();

      // A new AuthController/AccountModeController pair models a process restart.
      tokenStore.token = 'restored-user-a-token';
      final (_, AccountModeController restartedController) =
          await restoredSession(preferenceStore: preferences);
      await finishModeRestore(restartedController);

      expect(restartedController.mode, AccountMode.seller);
    },
  );

  test(
    'saved Seller Mode falls back to Buyer when capability is gone',
    () async {
      final _MemoryAccountModeStore preferences = _MemoryAccountModeStore()
        ..values[7] = AccountMode.seller.name;
      currentUser = userJson(id: 7, sellerCapability: 'buyer');

      final (_, AccountModeController controller) = await restoredSession(
        preferenceStore: preferences,
      );
      await finishModeRestore(controller);

      expect(controller.mode, AccountMode.buyer);
      expect(controller.canUseSellerMode, isFalse);
    },
  );
}
