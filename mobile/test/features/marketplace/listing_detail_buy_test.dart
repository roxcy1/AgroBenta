import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/transactions/widgets/buy_sheet.dart';
import 'package:agrobenta_mobile/models/listing.dart';
import 'package:agrobenta_mobile/models/transaction.dart';
import 'package:agrobenta_mobile/repositories/transaction_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/auth_fakes.dart';
import '../../support/marketplace_fakes.dart';
import '../../support/transaction_fakes.dart';

/// The Buy / Inquire sheet's own behaviour.
///
/// The listing detail screen offers a single Inquire action, so the sheet is
/// no longer reached from there. Its create path is still live and is tested
/// here through [BuySheet.show] directly, with the same rules as before: the
/// confirmation is explicit, and the body is exactly `listing_id` and
/// `quantity` — `total_amount` is server-derived (§6.1).
void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;
  late Future<Transaction?>? sheetResult;

  setUp(() {
    tokenStore = FakeTokenStore('token');
    recorded = <RecordedRequest>[];
    sheetResult = null;
  });

  Future<void> settle(WidgetTester tester, {int frames = 12}) async {
    for (int frame = 0; frame < frames; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Pumps a stand-in screen whose button opens the sheet exactly as the
  /// removed listing-detail action did, and taps it.
  Future<void> pumpSheet(WidgetTester tester) async {
    final TransactionRepository repository = buildTransactionRepository(
      tokenStore,
      (RecordedRequest request) async => request.method == 'POST'
          ? transactionCreatedResponse(
              transaction: transactionJson(id: 1, status: 'pending'),
            )
          : transactionListResponse(),
      recorded: recorded,
    );
    final Listing listing = Listing.fromJson(listingJson());

    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Center(
              child: FilledButton(
                onPressed: () {
                  sheetResult = BuySheet.show(
                    context,
                    listing: listing,
                    repository: repository,
                  );
                },
                child: const Text('Open buy sheet'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open buy sheet'));
    await settle(tester);
  }

  testWidgets('the sheet shows the listing, quantity and no live total', (
    WidgetTester tester,
  ) async {
    await pumpSheet(tester);

    expect(find.text('Buy / Inquire'), findsOneWidget);
    expect(find.text('Holstein'), findsOneWidget);
    expect(find.text('Quantity'), findsOneWidget);
    expect(find.text('Create transaction'), findsOneWidget);
    // No live total anywhere: the amount is server-derived (§6.1).
    expect(find.textContaining('Total'), findsNothing);
  });

  testWidgets('create confirms first, then sends only listing and quantity', (
    WidgetTester tester,
  ) async {
    await pumpSheet(tester);

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

    // The sheet closes with the record the server returned.
    final Transaction? created = await sheetResult;
    expect(created, isNotNull);
    expect(created!.id, 1);
    expect(created.status, TransactionStatus.pending);
  });

  testWidgets('backing out of the confirm dialog creates nothing', (
    WidgetTester tester,
  ) async {
    await pumpSheet(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Create transaction'));
    await settle(tester);
    expect(find.text('Create transaction?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await settle(tester);

    expect(find.text('Create transaction?'), findsNothing);
    expect(recorded.where((RecordedRequest r) => r.method == 'POST'), isEmpty);
    expect(find.text('Create transaction'), findsOneWidget);
  });
}
