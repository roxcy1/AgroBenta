import 'package:agrobenta_mobile/features/account_mode/state/account_mode.dart';
import 'package:agrobenta_mobile/features/buyer_shell/view/buyer_shell.dart';
import 'package:agrobenta_mobile/features/inquiries/view/received_inquiries_screen.dart';
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

  testWidgets('the Seller Home dashboard shows the real summary counts', (
    WidgetTester tester,
  ) async {
    final AccountModeShellHarness harness = await AccountModeShellHarness.pump(
      tester,
    );
    harness.select(AccountMode.seller);
    await settleAccountModeShell(tester);

    expect(find.text('Total listings across every status'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('Awaiting review'), findsOneWidget);
    expect(find.text('3 inquiries'), findsOneWidget);
    expect(find.text('4 recorded transactions'), findsOneWidget);
    expect(find.text('2 pending transactions.'), findsOneWidget);
    expect(
      harness.recorded
          .where((RecordedRequest r) => r.apiPath == '/seller/dashboard')
          .single
          .query,
      isEmpty,
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

    await tester.tap(find.text('Manage listings'));
    await tester.pump();

    final IndexedStack stack = tester.widget<IndexedStack>(
      find.byType(IndexedStack).first,
    );
    expect(stack.index, 1);
  });

  testWidgets('the Seller Home entry switches to the Transactions tab', (
    WidgetTester tester,
  ) async {
    final AccountModeShellHarness harness = await AccountModeShellHarness.pump(
      tester,
    );
    harness.select(AccountMode.seller);
    await settleAccountModeShell(tester);

    await tester.ensureVisible(find.text('View transactions'));
    await tester.pump();
    await tester.tap(find.text('View transactions'));
    await tester.pump();

    final IndexedStack stack = tester.widget<IndexedStack>(
      find.byType(IndexedStack).first,
    );
    expect(stack.index, 3);
  });

  testWidgets('the Seller Home entry opens the received-inquiry inbox', (
    WidgetTester tester,
  ) async {
    final AccountModeShellHarness harness = await AccountModeShellHarness.pump(
      tester,
    );
    harness.select(AccountMode.seller);
    await settleAccountModeShell(tester);

    await tester.ensureVisible(find.text('View inquiries'));
    await tester.pump();
    await tester.tap(find.text('View inquiries'));
    await settleAccountModeShell(tester);

    expect(find.byType(ReceivedInquiriesScreen), findsOneWidget);
    expect(find.text('Maria Santos'), findsOneWidget);
    expect(find.text('Is this one still available?'), findsOneWidget);
    expect(
      harness.recorded
          .where((RecordedRequest r) => r.apiPath == '/seller/inquiries')
          .single
          .query,
      <String, String>{'page': '1', 'per_page': '15'},
    );
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
