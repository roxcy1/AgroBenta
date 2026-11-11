import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/seller_dashboard/state/seller_activity_scope.dart';
import 'package:agrobenta_mobile/features/seller_dashboard/view/all_activities_screen.dart';
import 'package:agrobenta_mobile/repositories/seller_activity_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/seller_dashboard_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;

  setUp(() {
    tokenStore = FakeTokenStore('token');
    recorded = <RecordedRequest>[];
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    required Future<http.Response> Function(RecordedRequest request) handler,
    VoidCallback? onOpenMessages,
    VoidCallback? onOpenTransactions,
    ValueChanged<int>? onOpenTransaction,
  }) async {
    final SellerActivityRepository repository = buildSellerActivityRepository(
      tokenStore,
      handler,
      recorded: recorded,
    );

    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      SellerActivityScope(
        repository: repository,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: AllActivitiesScreen(
            onOpenMessages: onOpenMessages ?? () {},
            onOpenListings: () {},
            onOpenTransactions: onOpenTransactions ?? () {},
            onOpenTransaction: onOpenTransaction,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  testWidgets('renders events and shows the filter chips', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      handler: (_) async => sellerActivityResponse(
        activities: <Map<String, dynamic>>[
          sellerActivityJson(label: 'Offer accepted'),
        ],
      ),
    );

    expect(find.text('All Activities'), findsOneWidget);
    expect(find.text('Offer accepted'), findsOneWidget);
    for (final String label in <String>[
      'All',
      'Listings',
      'Inquiries',
      'Offers',
      'Transactions',
      'All Time',
      'Today',
      'Last 7 Days',
      'Last 30 Days',
      'Custom Range',
    ]) {
      expect(find.text(label), findsWidgets, reason: 'missing $label');
    }
  });

  testWidgets('a category chip filters server-side', (WidgetTester tester) async {
    await pumpScreen(
      tester,
      handler: (_) async => sellerActivityResponse(),
    );

    await tester.tap(find.byKey(const ValueKey<String>('activity-category-offers')));
    await tester.pumpAndSettle();

    expect(recorded.last.query['category'], 'offers');
    expect(recorded.last.query['page'], '1');
  });

  testWidgets('the Today preset sends the current date boundary', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      handler: (_) async => sellerActivityResponse(),
    );

    await tester.tap(find.byKey(const ValueKey<String>('activity-date-today')));
    await tester.pumpAndSettle();

    final String today = isoDate(DateTime.now());
    expect(recorded.last.query['from'], today);
    expect(recorded.last.query['to'], today);
  });

  testWidgets('Clear resets category and dates', (WidgetTester tester) async {
    await pumpScreen(
      tester,
      handler: (_) async => sellerActivityResponse(),
    );

    await tester.tap(find.byKey(const ValueKey<String>('activity-category-listings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    final Map<String, String> query = recorded.last.query;
    expect(query.containsKey('category'), isFalse);
    expect(query.containsKey('from'), isFalse);
    expect(query.containsKey('to'), isFalse);
  });

  testWidgets('an empty filtered result explains itself', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      handler: (_) async => sellerActivityResponse(),
    );

    await tester.tap(find.byKey(const ValueKey<String>('activity-category-offers')));
    await tester.pumpAndSettle();

    expect(find.text('No activities match these filters.'), findsOneWidget);
  });

  testWidgets('an error offers retry and recovers', (WidgetTester tester) async {
    int calls = 0;
    await pumpScreen(
      tester,
      handler: (_) async {
        calls++;
        return calls == 1
            ? sellerActivityResponse(statusCode: 500)
            : sellerActivityResponse(
                activities: <Map<String, dynamic>>[sellerActivityJson()],
              );
      },
    );

    expect(find.text('Something went wrong on the server.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('Offer accepted'), findsOneWidget);
  });

  testWidgets('rows navigate to their existing destinations', (
    WidgetTester tester,
  ) async {
    bool messages = false;
    int? transactionId;

    await pumpScreen(
      tester,
      handler: (_) async => sellerActivityResponse(
        activities: <Map<String, dynamic>>[
          sellerActivityJson(
            action: 'inquiry_created',
            label: 'Inquiry created',
          ),
          sellerActivityJson(
            id: 2,
            action: 'transaction_cancelled',
            label: 'Transaction cancelled',
            transactionId: 42,
          ),
        ],
      ),
      onOpenMessages: () => messages = true,
      onOpenTransaction: (int id) => transactionId = id,
    );

    await tester.tap(find.text('Inquiry created'));
    await tester.tap(find.text('Transaction cancelled'));
    await tester.pumpAndSettle();

    expect(messages, isTrue);
    expect(transactionId, 42);
  });
}
