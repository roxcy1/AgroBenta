import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/core/utils/app_formatters.dart';
import 'package:agrobenta_mobile/features/offers/state/offer_scope.dart';
import 'package:agrobenta_mobile/features/offers/view/make_offer_screen.dart';
import 'package:agrobenta_mobile/models/inquiry.dart';
import 'package:agrobenta_mobile/repositories/offer_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/offer_fakes.dart';

/// A date that is always after the form's "tomorrow" floor, so the
/// expired-preference fallback never fires. Built from the wall clock rather
/// than a literal, so the test cannot go stale as time passes.
DateTime futurePickupDate() {
  final DateTime now = DateTime.now();
  return DateTime(now.year, now.month, now.day + 30);
}

/// The `yyyy-MM-dd` shape the API validates and `OfferService` sends.
String isoDate(DateTime date) {
  final String month = date.month.toString().padLeft(2, '0');
  final String day = date.day.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-$month-$day';
}

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  setUp(() {
    tokenStore = FakeTokenStore('1|mobile-token');
    recorded = <RecordedRequest>[];
  });

  Future<void> pumpForm(
    WidgetTester tester, {
    required Future<http.Response> Function(RecordedRequest request) handler,
    DateTime? preferredSchedule,
  }) async {
    final OfferRepository repository = buildOfferRepository(
      tokenStore,
      handler,
      recorded: recorded,
    );

    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      OfferScope(
        repository: repository,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: MakeOfferScreen.forConversation(
            inquiryId: 55,
            listingId: 12,
            buyerName: 'Pedro Reyes',
            listingTitle: 'Holstein Heifer',
            askingPrice: '50000.00',
            paymentMethod: InquiryPaymentMethod.gcash,
            collectionMethod: InquiryCollectionMethod.farmPickup,
            preferredSchedule: preferredSchedule ?? futurePickupDate(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('prefills the inquiry facts and terms as read-only context', (
    WidgetTester tester,
  ) async {
    await pumpForm(tester, handler: (_) async => offerCreatedResponse());

    expect(find.text('Pedro Reyes'), findsOneWidget);
    expect(find.text('Holstein Heifer'), findsOneWidget);
    expect(find.textContaining('50,000'), findsOneWidget);
    expect(find.text('GCash'), findsOneWidget);
    expect(find.text('Pick up from the seller\'s farm'), findsOneWidget);
    expect(find.textContaining('Buyer did not choose one'), findsNothing);

    // The price field starts at the listing's asking price, editable.
    final TextField amount = tester.widget<TextField>(
      find.byType(TextField).first,
    );
    expect(amount.controller?.text, '50000.00');
  });

  testWidgets('a passed preferred date defaults to tomorrow and is marked', (
    WidgetTester tester,
  ) async {
    await pumpForm(
      tester,
      preferredSchedule: DateTime(2020, 1, 1),
      handler: (_) async => offerCreatedResponse(),
    );

    final DateTime tomorrow = DateTime.now().add(const Duration(days: 1));
    expect(
      find.text(AppFormatters.formatDate(tomorrow)),
      findsOneWidget,
      reason: 'the picker starts on a future date, not the expired one',
    );
    expect(
      find.text('changed'),
      findsOneWidget,
      reason: 'the original preference is preserved for comparison',
    );
  });

  testWidgets('sends the editable terms with the offer', (
    WidgetTester tester,
  ) async {
    final DateTime pickup = futurePickupDate();
    await pumpForm(
      tester,
      preferredSchedule: pickup,
      handler: (_) async => offerCreatedResponse(
        offer: offerJson(id: 9, proposedAmount: '47000.00'),
      ),
    );

    await tester.enterText(find.byType(TextField).first, '47000.00');
    await tester.ensureVisible(find.text('Send offer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send offer'));
    await tester.pumpAndSettle();

    final RecordedRequest post = recorded.single;
    expect(post.method, 'POST');
    expect(post.apiPath, '/offers');
    expect(post.body['inquiry_id'], 55);
    expect(post.body['listing_id'], 12);
    expect(post.body['proposed_amount'], '47000.00');
    // Prefilled terms travel unchanged because the seller kept them.
    expect(post.body['payment_method'], 'gcash');
    expect(post.body['collection_method'], 'farm_pickup');
    expect(post.body['proposed_pickup_date'], isoDate(pickup));

    expect(find.text('Offer sent'), findsOneWidget);
  });
}
