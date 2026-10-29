import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:agrobenta_mobile/features/seller_listings/state/seller_listing_controller.dart';
import 'package:agrobenta_mobile/features/seller_listings/state/seller_listing_scope.dart';
import 'package:agrobenta_mobile/features/seller_listings/view/seller_listing_detail_screen.dart';
import 'package:agrobenta_mobile/repositories/seller_listing_repository.dart';
import 'package:agrobenta_mobile/models/listing.dart';

import '../../support/seller_listing_fakes.dart';

/// Pumps the detail screen over a mock transport, with the given listing as the
/// snapshot. `loadInitial()` runs after the first frame, so the handler should
/// answer `GET /seller/listings` with the listing present.
Future<void> pumpDetailScreen(
  WidgetTester tester, {
  required Listing listing,
  required Future<http.Response> Function(RecordedRequest request) handler,
}) async {
  final SellerListingRepository repository = buildSellerListingRepository(
    FakeTokenStore('1|test-mobile-token'),
    handler,
  );
  final SellerListingController controller = SellerListingController(
    repository,
  );
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    SellerListingScope(
      repository: repository,
      controller: controller,
      child: MaterialApp(
        theme: ThemeData.light(),
        home: SellerListingDetailScreen(listing: listing),
      ),
    ),
  );

  // Let `loadInitial()` run its post-frame callback and settle.
  for (int frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A `GET /seller/listings` response containing exactly one listing.
http.Response sellerListingSingleResponse({
  required Listing listing,
  int statusCode = 200,
}) => http.Response(
  jsonEncode(<String, dynamic>{
    'success': true,
    'message': null,
    'data': <String, dynamic>{
      'listings': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': listing.id,
          'seller': <String, dynamic>{'id': listing.seller.id, 'name': listing.seller.name},
          'livestock_type': listing.livestockType,
          'breed': listing.breed,
          'age_value': listing.ageValue,
          'age_unit': listing.ageUnit,
          'gender': listing.gender,
          'weight_value': listing.weightValue,
          'weight_unit': listing.weightUnit,
          'quantity': listing.quantity,
          'asking_price': listing.askingPrice,
          'location': listing.location,
          'health_status': listing.healthStatus,
          'vaccination': listing.vaccination,
          'short_description': listing.shortDescription,
          'additional_notes': listing.additionalNotes,
          'photos': <Object?>[],
          'status': listing.status.value,
          'created_at': listing.createdAt?.toIso8601String(),
          'updated_at': listing.updatedAt?.toIso8601String(),
        },
      ],
      'pagination': <String, dynamic>{
        'current_page': 1,
        'last_page': 1,
        'per_page': 15,
        'total': 1,
      },
    },
  }),
  statusCode,
  headers: <String, String>{'content-type': 'application/json'},
);

/// Build a [Listing] from [listingJson] fixture with an optional status.
Listing fixtureListing({
  int id = 1,
  String status = 'active',
}) =>
    Listing.fromJson(listingJson(id: id, status: status));

void main() {
  testWidgets('a draft detail screen offers Delete and Submit for review', (
    WidgetTester tester,
  ) async {
    final Listing draft = fixtureListing(id: 1, status: 'draft');

    await pumpDetailScreen(
      tester,
      listing: draft,
      handler: (RecordedRequest request) async {
        if (request.apiPath == '/seller/listings') {
          return sellerListingSingleResponse(listing: draft);
        }
        return http.Response(
          jsonEncode(<String, dynamic>{'success': true, 'message': null, 'data': null}),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      },
    );

    // Delete is present for drafts.
    expect(find.widgetWithText(OutlinedButton, 'Delete listing'), findsOneWidget);

    // Submit for review is present for drafts.
    expect(find.widgetWithText(FilledButton, 'Submit for review'), findsOneWidget);
  });

  testWidgets('an active detail screen offers Mark as sold, not Delete', (
    WidgetTester tester,
  ) async {
    final Listing active = fixtureListing(id: 2, status: 'active');

    await pumpDetailScreen(
      tester,
      listing: active,
      handler: (RecordedRequest request) async {
        if (request.apiPath == '/seller/listings') {
          return sellerListingSingleResponse(listing: active);
        }
        return http.Response(
          jsonEncode(<String, dynamic>{'success': true, 'message': null, 'data': null}),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      },
    );

    expect(find.widgetWithText(OutlinedButton, 'Mark as sold'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Delete listing'), findsNothing);
  });

  testWidgets('markSold on the detail screen requires confirmation before acting', (
    WidgetTester tester,
  ) async {
    final Listing active = fixtureListing(id: 3, status: 'active');

    await pumpDetailScreen(
      tester,
      listing: active,
      handler: (RecordedRequest request) async {
        if (request.apiPath == '/seller/listings') {
          return sellerListingSingleResponse(listing: active);
        }
        if (request.apiPath.endsWith('/mark-sold')) {
          return sellerListingResponse(
            listing: listingJson(id: 3, status: 'sold'),
          );
        }
        return http.Response(
          jsonEncode(<String, dynamic>{'success': true, 'message': null, 'data': null}),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      },
    );

    // Tap Mark as sold — confirmation dialog must appear before any API call.
    expect(find.text('Mark this listing as sold?'), findsNothing);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Mark as sold'));
    await tester.pumpAndSettle();

    // Dialog is shown with Cancel and Confirm.
    expect(find.text('Mark this listing as sold?'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Mark as sold'), findsOneWidget);

    // Cancel closes the dialog without changing listing state.
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Mark this listing as sold?'), findsNothing);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Sold'), findsNothing);

    // Confirm closes the dialog.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Mark as sold'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Mark as sold'));
    await tester.pumpAndSettle();
    expect(find.text('Mark this listing as sold?'), findsNothing);
  });

  testWidgets('an inactive detail screen offers Delete only', (
    WidgetTester tester,
  ) async {
    final Listing inactive = fixtureListing(id: 4, status: 'inactive');

    await pumpDetailScreen(
      tester,
      listing: inactive,
      handler: (RecordedRequest request) async {
        if (request.apiPath == '/seller/listings') {
          return sellerListingSingleResponse(listing: inactive);
        }
        return http.Response(
          jsonEncode(<String, dynamic>{'success': true, 'message': null, 'data': null}),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      },
    );

    expect(find.widgetWithText(OutlinedButton, 'Delete listing'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Submit for review'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Mark as sold'), findsNothing);
  });

  for (final String status in <String>['pending', 'sold']) {
    testWidgets('a $status detail screen offers no action', (
      WidgetTester tester,
    ) async {
      final Listing listing = fixtureListing(id: 5, status: status);

      await pumpDetailScreen(
        tester,
        listing: listing,
        handler: (RecordedRequest request) async {
          if (request.apiPath == '/seller/listings') {
            return sellerListingSingleResponse(listing: listing);
          }
          return http.Response(
            jsonEncode(<String, dynamic>{'success': true, 'message': null, 'data': null}),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        },
      );

      expect(find.widgetWithText(OutlinedButton, 'Delete listing'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Submit for review'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Mark as sold'), findsNothing);
    });
  }
}
