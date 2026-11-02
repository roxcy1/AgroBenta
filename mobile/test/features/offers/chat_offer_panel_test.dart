import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/offers/state/offer_state.dart';
import 'package:agrobenta_mobile/features/offers/widgets/chat_offer_panel.dart';
import 'package:agrobenta_mobile/models/offer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/offer_fakes.dart';

void main() {
  Future<void> pumpPanel(
    WidgetTester tester, {
    required Offer offer,
    required int currentUserId,
    ChatOffersStatus status = ChatOffersStatus.ready,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              ChatOfferPanel(
                state: ChatOffersState(status: status, offers: <Offer>[offer]),
                currentUserId: currentUserId,
                onAccept: (_) {},
                onDecline: (_) {},
                onWithdraw: (_) {},
                onRetry: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('a buyer sees the amount, status and both responses', (
    WidgetTester tester,
  ) async {
    await pumpPanel(
      tester,
      offer: Offer.fromJson(
        offerJson(buyerId: 7, sellerId: 3, proposedAmount: '48000.00'),
      ),
      currentUserId: 7,
    );

    expect(find.text('Purchase offer'), findsOneWidget);
    expect(find.text('₱48,000.00'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Accept offer'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
    expect(find.text('Withdraw offer'), findsNothing);
  });

  testWidgets('the seller sees withdraw, never the buyer responses', (
    WidgetTester tester,
  ) async {
    await pumpPanel(
      tester,
      offer: Offer.fromJson(offerJson(buyerId: 7, sellerId: 3)),
      currentUserId: 3,
    );

    expect(find.text('Withdraw offer'), findsOneWidget);
    expect(find.text('Accept offer'), findsNothing);
    expect(find.text('Decline'), findsNothing);
  });

  testWidgets('a terminal offer shows no action', (WidgetTester tester) async {
    await pumpPanel(
      tester,
      offer: Offer.fromJson(offerJson(status: 'accepted')),
      currentUserId: 7,
    );

    expect(find.text('Accepted'), findsOneWidget);
    expect(find.text('Accept offer'), findsNothing);
    expect(find.text('Decline'), findsNothing);
    expect(find.text('Withdraw offer'), findsNothing);
  });

  testWidgets('every pending offer stays actionable', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ChatOfferPanel(
            state: ChatOffersState(
              status: ChatOffersStatus.ready,
              offers: <Offer>[
                Offer.fromJson(
                  offerJson(id: 2, proposedAmount: '50000.00', buyerId: 7),
                ),
                Offer.fromJson(
                  offerJson(id: 1, proposedAmount: '48000.00', buyerId: 7),
                ),
              ],
            ),
            currentUserId: 7,
            onAccept: (_) {},
            onDecline: (_) {},
            onWithdraw: (_) {},
            onRetry: () {},
          ),
        ),
      ),
    );

    expect(find.text('Purchase offers'), findsOneWidget);
    expect(find.text('₱50,000.00'), findsOneWidget);
    expect(find.text('₱48,000.00'), findsOneWidget);
    expect(
      find.text('Accept offer'),
      findsNWidgets(2),
      reason: 'a newer offer must not hide an older pending one',
    );
  });

  testWidgets('an empty panel renders nothing at all', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ChatOfferPanel(
            state: const ChatOffersState(status: ChatOffersStatus.ready),
            currentUserId: 7,
            onAccept: (_) {},
            onDecline: (_) {},
            onWithdraw: (_) {},
            onRetry: () {},
          ),
        ),
      ),
    );

    expect(find.text('Purchase offer'), findsNothing);
    expect(find.text('Accept offer'), findsNothing);
  });

  testWidgets('the buyer sees the proposed terms and what the seller changed', (
    WidgetTester tester,
  ) async {
    await pumpPanel(
      tester,
      offer: Offer.fromJson(
        offerJson(
          buyerId: 7,
          sellerId: 3,
          proposedAmount: '47000.00',
          proposedPickupDate: '2026-11-12',
          paymentMethod: 'cash',
          collectionMethod: 'farm_pickup',
          note: 'Bring a helper.',
          originalTerms: <String, dynamic>{
            'payment_method': 'gcash',
            'collection_method': 'farm_pickup',
            'pickup_date': '2026-11-10',
          },
        ),
      ),
      currentUserId: 7,
    );

    expect(find.text('Pickup'), findsOneWidget);
    expect(find.textContaining('Cash (was GCash)'), findsOneWidget);
    expect(
      find.textContaining('Pick up from the seller'),
      findsOneWidget,
      reason: 'an unchanged term is shown once, without a "was" clause',
    );
    expect(find.text('Bring a helper.'), findsOneWidget);
    expect(find.text('Accept offer'), findsOneWidget);
  });

  testWidgets('the seller sees the same terms without change highlighting', (
    WidgetTester tester,
  ) async {
    await pumpPanel(
      tester,
      offer: Offer.fromJson(
        offerJson(
          buyerId: 7,
          sellerId: 3,
          paymentMethod: 'cash',
          originalTerms: <String, dynamic>{
            'payment_method': 'gcash',
            'collection_method': null,
            'pickup_date': null,
          },
        ),
      ),
      currentUserId: 3,
    );

    expect(find.text('Cash'), findsOneWidget);
    expect(find.textContaining('was GCash'), findsNothing);
    expect(find.text('Withdraw offer'), findsOneWidget);
  });
}
