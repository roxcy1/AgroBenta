import 'dart:async';

import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/seller_dashboard/state/seller_dashboard_scope.dart';
import 'package:agrobenta_mobile/features/seller_dashboard/view/seller_dashboard_view.dart';
import 'package:agrobenta_mobile/repositories/seller_dashboard_repository.dart';
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

  SellerDashboardRepository repository(
    Future<http.Response> Function(RecordedRequest request) handler,
  ) {
    return buildSellerDashboardRepository(
      tokenStore,
      handler,
      recorded: recorded,
    );
  }

  Future<void> pumpView(
    WidgetTester tester,
    SellerDashboardRepository dashboardRepository, {
    VoidCallback? onOpenListings,
    VoidCallback? onOpenInquiries,
    VoidCallback? onOpenTransactions,
  }) async {
    await tester.pumpWidget(
      SellerDashboardScope(
        repository: dashboardRepository,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SellerDashboardView(
              onOpenListings: onOpenListings ?? () {},
              onOpenInquiries: onOpenInquiries ?? () {},
              onOpenTransactions: onOpenTransactions ?? () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows a loading state before the first response', (
    WidgetTester tester,
  ) async {
    final Completer<http.Response> response = Completer<http.Response>();
    await pumpView(tester, repository((_) => response.future));
    await tester.pump();

    expect(find.text('Loading your dashboard...'), findsOneWidget);

    response.complete(sellerDashboardResponse());
    await tester.pumpAndSettle();
  });

  testWidgets('shows the exact counts returned by the API', (
    WidgetTester tester,
  ) async {
    await pumpView(tester, repository((_) async => sellerDashboardResponse()));
    await tester.pumpAndSettle();

    expect(find.text('Total listings across every status'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('Awaiting review'), findsOneWidget);
    expect(find.text('3 inquiries'), findsOneWidget);
    expect(find.text('4 recorded transactions'), findsOneWidget);
    expect(find.text('2 pending transactions.'), findsOneWidget);
    expect(recorded.single.apiPath, '/seller/dashboard');
  });

  testWidgets('renders an empty state when every count is zero', (
    WidgetTester tester,
  ) async {
    bool openedListings = false;
    await pumpView(
      tester,
      repository(
        (_) async => sellerDashboardResponse(
          dashboard: sellerDashboardJson(
            totalListings: 0,
            draft: 0,
            pendingListings: 0,
            active: 0,
            sold: 0,
            inactive: 0,
            totalInquiries: 0,
            totalTransactions: 0,
            pendingTransactions: 0,
          ),
        ),
      ),
      onOpenListings: () => openedListings = true,
    );
    await tester.pumpAndSettle();

    expect(find.text('No seller activity yet'), findsOneWidget);
    expect(find.text('Manage listings'), findsOneWidget);

    await tester.tap(find.text('Manage listings'));
    expect(openedListings, isTrue);
  });

  testWidgets('a first-load failure offers retry and recovers', (
    WidgetTester tester,
  ) async {
    final List<http.Response Function()> responses = <http.Response Function()>[
      sellerDashboardServerErrorResponse,
      sellerDashboardResponse,
    ];
    await pumpView(tester, repository((_) async => responses.removeAt(0)()));
    await tester.pumpAndSettle();

    expect(find.text('Could not load your dashboard'), findsOneWidget);
    expect(find.text('Something went wrong on the server.'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('Could not load your dashboard'), findsNothing);
    expect(find.text('3 inquiries'), findsOneWidget);
  });

  testWidgets('a failed refresh keeps the dashboard and shows a notice', (
    WidgetTester tester,
  ) async {
    final List<http.Response Function()> responses = <http.Response Function()>[
      sellerDashboardResponse,
      sellerDashboardServerErrorResponse,
    ];
    await pumpView(tester, repository((_) async => responses.removeAt(0)()));
    await tester.pumpAndSettle();

    final Future<void> refresh = tester
        .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
        .show();
    await tester.pump();
    await tester.pumpAndSettle();
    await refresh;

    expect(find.text('3 inquiries'), findsOneWidget);
    expect(find.text('Something went wrong on the server.'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('each section opens its existing seller destination', (
    WidgetTester tester,
  ) async {
    bool openedListings = false;
    bool openedInquiries = false;
    bool openedTransactions = false;
    await pumpView(
      tester,
      repository((_) async => sellerDashboardResponse()),
      onOpenListings: () => openedListings = true,
      onOpenInquiries: () => openedInquiries = true,
      onOpenTransactions: () => openedTransactions = true,
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Manage listings'));
    await tester.pump();
    await tester.tap(find.text('Manage listings'));

    await tester.ensureVisible(find.text('View inquiries'));
    await tester.pump();
    await tester.tap(find.text('View inquiries'));

    await tester.ensureVisible(find.text('View transactions'));
    await tester.pump();
    await tester.tap(find.text('View transactions'));

    expect(openedListings, isTrue);
    expect(openedInquiries, isTrue);
    expect(openedTransactions, isTrue);
  });
}
