import 'dart:convert';

import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_controller.dart';
import 'package:agrobenta_mobile/features/auth/state/auth_scope.dart';
import 'package:agrobenta_mobile/features/marketplace/state/marketplace_controller.dart';
import 'package:agrobenta_mobile/features/marketplace/state/marketplace_scope.dart';
import 'package:agrobenta_mobile/features/marketplace/views/listing_detail_screen.dart';
import 'package:agrobenta_mobile/features/transactions/state/transaction_scope.dart';
import 'package:agrobenta_mobile/features/transactions/views/transaction_detail_screen.dart';
import 'package:agrobenta_mobile/repositories/marketplace_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/marketplace_fakes.dart';
import '../../support/transaction_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  setUp(() {
    tokenStore = FakeTokenStore('token');
    recorded = <RecordedRequest>[];
  });

  Future<void> settle(WidgetTester tester, {int frames = 12}) async {
    for (int frame = 0; frame < frames; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Pumps the listing detail as the app does: scopes above `MaterialApp`,
  /// one transport answering every endpoint the screen can reach.
  Future<void> pumpDetail(
    WidgetTester tester, {
    required int sellerId,
    required int viewerId,
  }) async {
    Future<http.Response> transport(RecordedRequest request) async {
      switch (request.apiPath) {
        case '/listings/12':
          return listingDetailResponse(
            listing: listingJson(seller: sellerJson(id: sellerId)),
          );
        case '/transactions':
          if (request.method == 'POST') {
            return transactionCreatedResponse(
              transaction: transactionJson(id: 1, status: 'pending'),
            );
          }
          return transactionListResponse();
        case '/transactions/1':
          return transactionDetailResponse(
            transaction: transactionJson(id: 1, status: 'pending'),
          );
        default:
          return marketplaceListResponse();
      }
    }

    final MarketplaceRepository marketplaceRepository =
        buildMarketplaceRepository(
          tokenStore,
          transport,
          recorded: recorded,
        );
    final MarketplaceController marketplaceController = MarketplaceController(
      marketplaceRepository,
    );
    addTearDown(marketplaceController.dispose);

    final AuthController authController = AuthController(
      buildAuthRepository(
        tokenStore,
        (_) async => http.Response(
          jsonEncode(successEnvelope(data: userJson(id: viewerId))),
          200,
        ),
      ),
    );
    addTearDown(authController.dispose);
    tokenStore.token = 'stored-token';
    await authController.restoreSession();

    final transactionRepository = buildTransactionRepository(
      tokenStore,
      transport,
      recorded: recorded,
    );

    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AuthScope(
        controller: authController,
        child: MarketplaceScope(
          repository: marketplaceRepository,
          controller: marketplaceController,
          child: TransactionScope(
            repository: transactionRepository,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const ListingDetailScreen(listingId: 12),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets("a seller viewing their own listing sees no Buy / Inquire", (
    WidgetTester tester,
  ) async {
    // The viewer owns this listing (seller 7, viewer 7): a seller has no
    // create endpoint and cannot transact with themselves (§6.2).
    await pumpDetail(tester, sellerId: 7, viewerId: 7);

    expect(find.text('Holstein'), findsOneWidget);
    expect(find.text('Buy / Inquire'), findsNothing);
    expect(
      recorded.where((RecordedRequest r) => r.method == 'POST'),
      isEmpty,
    );
  });

  testWidgets('another viewer gets Buy / Inquire and the sheet', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester, sellerId: 3, viewerId: 7);

    expect(find.widgetWithText(FilledButton, 'Buy / Inquire'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Buy / Inquire'));
    await settle(tester);

    expect(find.text('Buy / Inquire'), findsWidgets);
    expect(find.text('Quantity'), findsOneWidget);
    expect(find.text('Create transaction'), findsOneWidget);
    // No live total anywhere: the amount is server-derived (§6.1).
    expect(find.textContaining('Total'), findsNothing);
  });

  testWidgets('create confirms first, then sends only listing and quantity', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester, sellerId: 3, viewerId: 7);
    await tester.tap(find.widgetWithText(FilledButton, 'Buy / Inquire'));
    await settle(tester);

    // Quantity selector: 1 -> 2.
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await settle(tester, frames: 2);

    await tester.tap(find.widgetWithText(FilledButton, 'Create transaction'));
    await settle(tester);

    expect(find.text('Create transaction?'), findsOneWidget);
    expect(
      find.textContaining('The final amount is set by the server.'),
      findsOneWidget,
    );
    expect(
      recorded.where((RecordedRequest r) => r.method == 'POST'),
      isEmpty,
      reason: 'the irreversible create waits for an explicit yes',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await settle(tester);

    final List<RecordedRequest> posts = recorded
        .where((RecordedRequest r) => r.method == 'POST')
        .toList(growable: false);
    expect(posts, hasLength(1));
    expect(posts.single.apiPath, '/transactions');
    expect(
      posts.single.body.keys.toSet(),
      <String>{'listing_id', 'quantity'},
      reason:
          'the body allow-list is exactly these two fields — buyer_id, '
          'seller_id, total_amount and status are server-derived and must '
          'never be sent (§6.1)',
    );
    expect(posts.single.body['listing_id'], 12);
    expect(posts.single.body['quantity'], 2);

    // The created pending record opens on the detail screen.
    expect(find.byType(TransactionDetailScreen), findsOneWidget);
    expect(find.text('TRX-001'), findsOneWidget);
    expect(find.text('Ongoing'), findsOneWidget);
  });

  testWidgets('backing out of the confirm dialog creates nothing', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester, sellerId: 3, viewerId: 7);
    await tester.tap(find.widgetWithText(FilledButton, 'Buy / Inquire'));
    await settle(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Create transaction'));
    await settle(tester);
    expect(find.text('Create transaction?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await settle(tester);

    expect(find.text('Create transaction?'), findsNothing);
    expect(
      recorded.where((RecordedRequest r) => r.method == 'POST'),
      isEmpty,
    );
    expect(find.text('Create transaction'), findsOneWidget);
  });
}
