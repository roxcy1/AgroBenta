import 'package:agrobenta_mobile/widgets/verified_seller_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('exposes a single accessible Verified Seller label', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: VerifiedSellerBadge())),
    );

    expect(find.text('Verified Seller'), findsOneWidget);
    expect(find.bySemanticsLabel('Verified Seller'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('compact badge remains visible at narrow widths', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(180, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: VerifiedSellerBadge(compact: true),
          ),
        ),
      ),
    );

    expect(find.text('Verified'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
