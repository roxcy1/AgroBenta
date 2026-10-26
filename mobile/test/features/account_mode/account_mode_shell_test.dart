import 'package:agrobenta_mobile/features/account_mode/state/account_mode.dart';
import 'package:agrobenta_mobile/features/buyer_shell/view/buyer_shell.dart';
import 'package:agrobenta_mobile/features/seller_shell/view/seller_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/account_mode_shell_harness.dart';
import '../../support/auth_fakes.dart';

void main() {
  testWidgets('starts in Buyer Mode and switches to the seller shell '
      'immediately', (WidgetTester tester) async {
    final AccountModeShellHarness harness = await AccountModeShellHarness.pump(
      tester,
    );

    expect(find.byType(BuyerShell), findsOneWidget);
    expect(find.byType(SellerShell), findsNothing);

    harness.select(AccountMode.seller);
    await settleAccountModeShell(tester);

    expect(find.byType(SellerShell), findsOneWidget);
    expect(find.byType(BuyerShell), findsNothing);
    expect(harness.accountModeController.mode, AccountMode.seller);

    harness.select(AccountMode.buyer);
    await settleAccountModeShell(tester);

    expect(find.byType(BuyerShell), findsOneWidget);
    expect(find.byType(SellerShell), findsNothing);
    expect(harness.accountModeController.mode, AccountMode.buyer);
  });

  testWidgets('the seller shell has only the five approved destinations in '
      'order', (WidgetTester tester) async {
    final AccountModeShellHarness harness = await AccountModeShellHarness.pump(
      tester,
    );
    harness.select(AccountMode.seller);
    await settleAccountModeShell(tester);

    final List<NavigationDestination> destinations = tester
        .widgetList<NavigationDestination>(find.byType(NavigationDestination))
        .toList(growable: false);

    expect(destinations.map((NavigationDestination d) => d.label), <String>[
      'Home',
      'My Listings',
      'Messages',
      'Transactions',
      'Profile',
    ]);
    expect(find.text('Browse'), findsNothing);
  });

  testWidgets('the seller shell queries sales, not purchases', (
    WidgetTester tester,
  ) async {
    final AccountModeShellHarness harness = await AccountModeShellHarness.pump(
      tester,
    );
    harness.select(AccountMode.seller);
    await settleAccountModeShell(tester);

    expect(
      harness.recorded
          .where((RecordedRequest r) => r.apiPath == '/transactions')
          .map((RecordedRequest r) => r.query['role']),
      contains('seller'),
    );
  });

  testWidgets('the Seller Home entry switches to the My Listings tab', (
    WidgetTester tester,
  ) async {
    final AccountModeShellHarness harness = await AccountModeShellHarness.pump(
      tester,
    );
    harness.select(AccountMode.seller);
    await settleAccountModeShell(tester);

    await tester.tap(find.text('Manage my listings'));
    await tester.pump();

    final IndexedStack stack = tester.widget<IndexedStack>(
      find.byType(IndexedStack).first,
    );
    expect(stack.index, 1);
  });

  testWidgets('a buyer cannot select Seller Mode and stays in BuyerShell', (
    WidgetTester tester,
  ) async {
    final AccountModeShellHarness harness = await AccountModeShellHarness.pump(
      tester,
      sellerCapability: 'buyer',
    );

    harness.select(AccountMode.seller);
    await settleAccountModeShell(tester);

    expect(find.byType(BuyerShell), findsOneWidget);
    expect(find.byType(SellerShell), findsNothing);
    expect(harness.accountModeController.mode, AccountMode.buyer);
    expect(harness.authController.state.user?.isSeller, isFalse);
  });
}
