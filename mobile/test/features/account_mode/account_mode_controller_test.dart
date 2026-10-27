import 'dart:convert';

import 'package:agrobenta_mobile/features/account_mode/state/account_mode.dart';
import 'package:agrobenta_mobile/features/account_mode/state/account_mode_controller.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;
  late Map<String, dynamic> currentUser;

  setUp(() {
    tokenStore = FakeTokenStore('stored-token');
    currentUser = userJson();
  });

  Future<http.Response> Function(RecordedRequest request) authHandler() {
    return (RecordedRequest request) async {
      if (request.apiPath == '/auth/logout') {
        return http.Response(
          jsonEncode(successEnvelope(message: 'Logged out successfully.')),
          200,
        );
      }
      return http.Response(jsonEncode(successEnvelope(data: currentUser)), 200);
    };
  }

  Future<(AuthController, AccountModeController)> restoredSession() async {
    final AuthController authController = AuthController(
      buildAuthRepository(tokenStore, authHandler()),
    );
    addTearDown(authController.dispose);

    await authController.restoreSession();

    final AccountModeController accountModeController = AccountModeController(
      authController,
    );
    addTearDown(accountModeController.dispose);

    return (authController, accountModeController);
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

  test('changing accounts clears Seller Mode', () async {
    currentUser = userJson(id: 7, sellerCapability: 'seller');
    final (AuthController auth, AccountModeController controller) =
        await restoredSession();
    controller.select(AccountMode.seller);

    currentUser = userJson(
      id: 8,
      name: 'Ben Cruz',
      email: 'ben@example.test',
      sellerCapability: 'seller',
    );
    await auth.refreshUser();

    expect(controller.mode, AccountMode.buyer);
    expect(controller.canUseSellerMode, isTrue);
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
}
