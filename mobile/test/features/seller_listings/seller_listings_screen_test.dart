import 'package:agrobenta_mobile/features/seller_listings/view/seller_listing_detail_screen.dart';
import 'package:agrobenta_mobile/features/seller_listings/view/seller_listing_form_screen.dart';
import 'package:agrobenta_mobile/features/seller_listings/view/seller_listing_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/seller_listing_fakes.dart';
import '../../support/seller_listings_app_harness.dart';

/// These tests exercise the screen against a real controller and fake HTTP, so
/// the status chips and the empty state are driven by the same published state
/// the app uses. The action-row rules themselves are the controller's and are
/// covered by the controller tests.
void main() {
  testWidgets('shows the empty state for a seller with no listings', (
    WidgetTester tester,
  ) async {
    await SellerListingsHarness.pump(
      tester,
      handler: (RecordedRequest request) async => sellerListingListResponse(
        listings: <Map<String, dynamic>>[],
        total: 0,
      ),
    );

    expect(
      find.text('No listings yet — Create your first listing'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Create a listing'),
      findsOneWidget,
    );
  });

  testWidgets('renders one card per listing with its status', (
    WidgetTester tester,
  ) async {
    await SellerListingsHarness.pump(
      tester,
      handler: (RecordedRequest request) async => sellerListingListResponse(
        listings: <Map<String, dynamic>>[
          listingJson(id: 1, livestockType: 'Cattle', status: 'draft'),
          listingJson(id: 2, livestockType: 'Goat', status: 'pending'),
          listingJson(id: 3, livestockType: 'Poultry', status: 'active'),
        ],
        total: 3,
      ),
    );

    // Scoped to the cards: the status words also appear as filter chips in the
    // header, so an unscoped finder would count both and report doubles.
    Finder inCards(String text) => find.descendant(
      of: find.byWidgetPredicate(
        (Widget widget) => widget.runtimeType.toString() == 'SellerListingCard',
      ),
      matching: find.text(text),
    );

    expect(inCards('Cattle'), findsOneWidget);
    expect(inCards('Draft'), findsOneWidget);
    expect(inCards('Pending review'), findsOneWidget);

    // The third card is built lazily; a short drag makes it appear. `last` is
    // the vertical list — the status filter row above it is horizontal and
    // comes earlier in the tree.
    await tester.drag(find.byType(ListView).last, const Offset(0, -200));
    await sellerListingsSettle(tester);

    expect(inCards('Active'), findsOneWidget);
  });

  testWidgets(
    'a seller without a match is told the query is empty, not the account',
    (WidgetTester tester) async {
      await SellerListingsHarness.pump(
        tester,
        handler: (RecordedRequest request) async => sellerListingListResponse(
          listings: <Map<String, dynamic>>[],
          total: 0,
        ),
      );
      await tester.enterText(find.byType(TextField).first, 'Cattle');
      await sellerListingsSettle(tester, frames: 20);

      expect(find.text('No listings match'), findsOneWidget);
      expect(
        find.text('No listings yet — Create your first listing'),
        findsNothing,
      );
    },
  );

  testWidgets('the create button opens the form', (WidgetTester tester) async {
    await SellerListingsHarness.pump(
      tester,
      handler: (RecordedRequest request) async => sellerListingListResponse(
        listings: <Map<String, dynamic>>[],
        total: 0,
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Create a listing'));
    await sellerListingsSettle(tester);

    expect(find.byType(SellerListingFormScreen), findsOneWidget);
  });

  testWidgets('tapping a card opens its detail', (WidgetTester tester) async {
    await SellerListingsHarness.pump(
      tester,
      handler: (RecordedRequest request) async => sellerListingListResponse(
        listings: <Map<String, dynamic>>[
          listingJson(id: 1, livestockType: 'Cattle', status: 'draft'),
        ],
        total: 1,
      ),
    );

    await tester.tap(find.text('Cattle'));
    await sellerListingsSettle(tester);

    expect(find.byType(SellerListingDetailScreen), findsOneWidget);
  });

  testWidgets('a draft without photos cannot be submitted from the list', (
    WidgetTester tester,
  ) async {
    await SellerListingsHarness.pump(
      tester,
      handler: (RecordedRequest request) async => sellerListingListResponse(
        listings: <Map<String, dynamic>>[
          listingJson(id: 1, livestockType: 'Cattle', status: 'draft'),
        ],
        total: 1,
      ),
    );

    expect(find.text(listingPhotoRequirementMessage), findsOneWidget);
    final TextButton submit = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Submit for review'),
    );
    expect(submit.onPressed, isNull);
  });

  testWidgets('a draft with a stored photo offers submission', (
    WidgetTester tester,
  ) async {
    await SellerListingsHarness.pump(
      tester,
      handler: (RecordedRequest request) async => sellerListingListResponse(
        listings: <Map<String, dynamic>>[
          listingJson(
            id: 1,
            livestockType: 'Cattle',
            status: 'draft',
            photos: <Object?>['https://api.test/storage/listings/a.jpg'],
          ),
        ],
        total: 1,
      ),
    );

    expect(find.text(listingPhotoRequirementMessage), findsNothing);
    final TextButton submit = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Submit for review'),
    );
    expect(submit.onPressed, isNotNull);
  });

  testWidgets('the detail screen blocks submit for a draft without photos', (
    WidgetTester tester,
  ) async {
    await SellerListingsHarness.pump(
      tester,
      handler: (RecordedRequest request) async => sellerListingListResponse(
        listings: <Map<String, dynamic>>[
          listingJson(id: 1, livestockType: 'Cattle', status: 'draft'),
        ],
        total: 1,
      ),
    );

    await tester.tap(find.text('Cattle'));
    await sellerListingsSettle(tester);

    expect(find.text(listingPhotoRequirementMessage), findsOneWidget);
    final FilledButton submit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Submit for review'),
    );
    expect(submit.onPressed, isNull);
  });

  testWidgets('an active listing offers Mark as sold from the list', (
    WidgetTester tester,
  ) async {
    await SellerListingsHarness.pump(
      tester,
      handler: (RecordedRequest request) async => sellerListingListResponse(
        listings: <Map<String, dynamic>>[
          listingJson(id: 1, livestockType: 'Cattle', status: 'active'),
        ],
        total: 1,
      ),
    );

    expect(find.text('Mark as sold'), findsOneWidget);
  });

  testWidgets('a pending listing does not offer Mark as sold', (
    WidgetTester tester,
  ) async {
    await SellerListingsHarness.pump(
      tester,
      handler: (RecordedRequest request) async => sellerListingListResponse(
        listings: <Map<String, dynamic>>[
          listingJson(id: 1, livestockType: 'Cattle', status: 'pending'),
        ],
        total: 1,
      ),
    );

    expect(find.text('Mark as sold'), findsNothing);
  });

  testWidgets('confirming Mark as sold shows sold status', (
    WidgetTester tester,
  ) async {
    await SellerListingsHarness.pump(
      tester,
      handler: (RecordedRequest request) async {
        if (request.apiPath.endsWith('/mark-sold')) {
          return sellerListingResponse(
            listing: listingJson(id: 1, status: 'sold'),
          );
        }
        return sellerListingListResponse(
          listings: <Map<String, dynamic>>[
            listingJson(id: 1, livestockType: 'Cattle', status: 'active'),
          ],
          total: 1,
        );
      },
    );

    await tester.tap(find.text('Mark as sold'));
    await sellerListingsSettle(tester);

    // Confirmation dialog appears.
    expect(find.text('Mark this listing as sold?'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Mark as sold'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Mark as sold'));
    await sellerListingsSettle(tester);

    // The sold listing is reflected in the list.
    expect(find.text('Sold'), findsWidgets);
  });
}

Future<void> sellerListingsSettle(
  WidgetTester tester, {
  int frames = 12,
}) async {
  for (int frame = 0; frame < frames; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
