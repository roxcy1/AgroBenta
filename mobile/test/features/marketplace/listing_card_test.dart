import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/marketplace/widgets/listing_card.dart';
import 'package:agrobenta_mobile/models/listing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/marketplace_fakes.dart';

void main() {
  testWidgets('shows seller name and badge only for a server-verified seller', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ListView(
            children: <Widget>[
              ListingCard(
                listing: Listing.fromJson(listingJson()),
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.textContaining('Rizal Farms'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ListView(
            children: <Widget>[
              ListingCard(
                listing: Listing.fromJson(
                  listingJson(seller: sellerJson(isVerified: false)),
                ),
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.textContaining('Rizal Farms'), findsOneWidget);
    expect(find.text('Verified'), findsNothing);
  });

  testWidgets('seller row does not overflow on a compact listing card', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(260, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 220,
            child: ListingCard(
              listing: Listing.fromJson(
                listingJson(
                  seller: sellerJson(
                    name: 'A very long livestock farm seller display name',
                  ),
                ),
              ),
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Verified'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
