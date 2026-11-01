import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/inquiries/state/inquiry_scope.dart';
import 'package:agrobenta_mobile/features/inquiries/view/received_inquiries_screen.dart';
import 'package:agrobenta_mobile/repositories/inquiry_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/inquiry_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  setUp(() {
    tokenStore = FakeTokenStore('token');
    recorded = <RecordedRequest>[];
  });

  Future<void> settle(WidgetTester tester, {int frames = 10}) async {
    for (int frame = 0; frame < frames; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    Future<http.Response> Function(RecordedRequest request) handler,
  ) async {
    final InquiryRepository repository = buildInquiryRepository(
      tokenStore,
      handler,
      recorded: recorded,
    );

    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      InquiryScope(
        repository: repository,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ReceivedInquiriesScreen(),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets(
    'shows the empty state, not an error, when there are no inquiries',
    (WidgetTester tester) async {
      await pumpScreen(
        tester,
        (_) async => sellerInquiryListResponse(
          inquiries: <Map<String, dynamic>>[],
          total: 0,
        ),
      );

      expect(find.text('Received Inquiries'), findsOneWidget);
      expect(find.text('No inquiries yet'), findsOneWidget);
      expect(find.text('Could not load received inquiries'), findsNothing);
      expect(recorded.single.apiPath, '/seller/inquiries');
    },
  );

  testWidgets('renders the buyer inquiry fields the resource carries', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      (_) async => sellerInquiryListResponse(
        inquiries: <Map<String, dynamic>>[
          sellerInquiryJson(
            buyer: inquiryBuyerJson(name: 'Maria Santos'),
            listing: inquiryListingJson(
              livestockType: 'Cattle',
              breed: 'Holstein',
            ),
            subject: 'Interested in your cattle',
            message: 'Is this one still available?',
            purchaseInterest: true,
            transactionMethod: 'direct_deal',
            deliveryMethod: 'buyer_pickup',
            contactMethod: 'in_app_message',
            preferredSchedule: '2026-10-25',
          ),
        ],
      ),
    );

    expect(find.text('Maria Santos'), findsOneWidget);
    expect(find.text('Cattle - Holstein'), findsOneWidget);
    expect(find.text('Interested in your cattle'), findsOneWidget);
    expect(find.text('Is this one still available?'), findsOneWidget);
    expect(find.text('Wants to buy'), findsOneWidget);
    expect(
      find.text('Direct Deal / Buyer Pickup / In-app Message'),
      findsOneWidget,
    );
    expect(find.text('Preferred date: 25 Oct 2026'), findsOneWidget);
    expect(find.text('Proposed delivery fee: ₱1,500.00'), findsOneWidget);
  });

  testWidgets('a deleted listing and missing buyer stay readable', (
    WidgetTester tester,
  ) async {
    final Map<String, dynamic> inquiry = sellerInquiryJson();
    inquiry['buyer'] = null;
    inquiry['listing'] = null;

    await pumpScreen(
      tester,
      (_) async =>
          sellerInquiryListResponse(inquiries: <Map<String, dynamic>>[inquiry]),
    );

    expect(find.text('Unknown buyer'), findsOneWidget);
    expect(find.text('Listing no longer available'), findsOneWidget);
    expect(find.text('Is this one still available?'), findsOneWidget);
  });

  testWidgets('a first-page failure shows the message and retries', (
    WidgetTester tester,
  ) async {
    int calls = 0;
    await pumpScreen(tester, (_) async {
      calls++;
      if (calls == 1) {
        return inquiryServerErrorResponse();
      }
      return sellerInquiryListResponse(
        inquiries: <Map<String, dynamic>>[
          sellerInquiryJson(buyer: inquiryBuyerJson(name: 'Ben Cruz')),
        ],
      );
    });

    expect(find.text('Could not load received inquiries'), findsOneWidget);
    expect(find.text('Something went wrong on the server.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await settle(tester);

    expect(find.text('Ben Cruz'), findsOneWidget);
    expect(recorded, hasLength(2));
  });
}
