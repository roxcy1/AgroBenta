import 'dart:async';

import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/seller_dashboard/state/seller_dashboard_scope.dart';
import 'package:agrobenta_mobile/features/seller_dashboard/view/seller_dashboard_view.dart';
import 'package:agrobenta_mobile/repositories/inquiry_repository.dart';
import 'package:agrobenta_mobile/repositories/seller_activity_repository.dart';
import 'package:agrobenta_mobile/repositories/seller_dashboard_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/auth_fakes.dart';
import '../../support/inquiry_fakes.dart';
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
    Future<void> Function()? onAddListing,
    InquiryRepository? inquiriesRepository,
    SellerActivityRepository? activityRepository,
    void Function(int buyerId, int? transactionId)? onOpenOffer,
    ValueChanged<int>? onOpenTransaction,
    VoidCallback? onSeeAllActivities,
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
              onAddListing: onAddListing ?? () async {},
              inquiriesRepository: inquiriesRepository,
              activityRepository: activityRepository,
              onOpenOffer: onOpenOffer,
              onOpenTransaction: onOpenTransaction,
              onSeeAllActivities: onSeeAllActivities,
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

  testWidgets('shows the exact counts in the summary grid', (
    WidgetTester tester,
  ) async {
    await pumpView(tester, repository((_) async => sellerDashboardResponse()));
    await tester.pumpAndSettle();

    expect(find.text('Active Listings'), findsOneWidget);
    expect(
      find.text('2'),
      findsNWidgets(2),
      reason: 'active listings and ongoing transactions are both 2',
    );
    expect(find.text('Inquiries'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Ongoing Transactions'), findsOneWidget);
    expect(find.text('Completed Sales'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(recorded.single.apiPath, '/seller/dashboard');
  });

  testWidgets('renders zero counts and the no-activity copy', (
    WidgetTester tester,
  ) async {
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
            completedTransactions: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No seller activity yet. Create your first listing to '
        'start receiving inquiries and recording transactions.'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(4));
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

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('Could not load your dashboard'), findsNothing);
    expect(find.text('Inquiries'), findsOneWidget);
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

    expect(find.text('Inquiries'), findsOneWidget);
    expect(find.text('Something went wrong on the server.'), findsOneWidget);
  });

  testWidgets('summary tiles navigate to their existing destinations', (
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

    await tester.tap(find.text('Active Listings'));
    await tester.tap(find.text('Inquiries'));
    await tester.tap(find.text('Ongoing Transactions'));
    await tester.tap(find.text('Completed Sales'));

    expect(openedListings, isTrue);
    expect(openedInquiries, isTrue);
    expect(openedTransactions, isTrue);
  });

  testWidgets('Add listing invokes the supplied action', (
    WidgetTester tester,
  ) async {
    int calls = 0;
    await pumpView(
      tester,
      repository((_) async => sellerDashboardResponse()),
      onAddListing: () async => calls++,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add listing'));
    await tester.pumpAndSettle();

    expect(calls, 1);
  });

  testWidgets('Needs Your Attention lists actionable inquiries only', (
    WidgetTester tester,
  ) async {
    final InquiryRepository inquiryRepository = buildInquiryRepository(
      tokenStore,
      (RecordedRequest request) async => sellerInquiryListResponse(
        inquiries: <Map<String, dynamic>>[
          sellerInquiryJson(
            buyer: inquiryBuyerJson(name: 'Maria Santos'),
            canMakeOffer: true,
          ),
          sellerInquiryJson(
            id: 6,
            buyer: inquiryBuyerJson(id: 10, name: 'Not Actionable'),
            canMakeOffer: false,
          ),
        ],
      ),
      recorded: recorded,
    );

    bool openedInquiries = false;
    await pumpView(
      tester,
      repository((_) async => sellerDashboardResponse()),
      inquiriesRepository: inquiryRepository,
      onOpenInquiries: () => openedInquiries = true,
    );
    await tester.pumpAndSettle();

    expect(find.text('Needs Your Attention'), findsOneWidget);
    expect(find.text('Maria Santos'), findsOneWidget);
    expect(find.text('Not Actionable'), findsNothing);
    expect(find.text('View inquiries'), findsOneWidget);

    await tester.tap(find.text('Maria Santos'));
    await tester.pumpAndSettle();
    expect(openedInquiries, isTrue);

    expect(
      recorded.where((RecordedRequest r) => r.apiPath == '/seller/inquiries'),
      hasLength(1),
    );
  });

  testWidgets('falls back to labelled recent inquiries when none are actionable', (
    WidgetTester tester,
  ) async {
    final InquiryRepository inquiryRepository = buildInquiryRepository(
      tokenStore,
      (RecordedRequest request) async => sellerInquiryListResponse(
        inquiries: <Map<String, dynamic>>[
          sellerInquiryJson(
            buyer: inquiryBuyerJson(name: 'Ana Reyes'),
            canMakeOffer: false,
          ),
        ],
      ),
      recorded: recorded,
    );

    await pumpView(
      tester,
      repository((_) async => sellerDashboardResponse()),
      inquiriesRepository: inquiryRepository,
    );
    await tester.pumpAndSettle();

    expect(find.text('Ana Reyes'), findsOneWidget);
    expect(find.text('View recent inquiries'), findsOneWidget);
  });

  SellerActivityRepository activityRepository(
    Future<http.Response> Function(RecordedRequest request) handler,
  ) {
    return buildSellerActivityRepository(
      tokenStore,
      handler,
      recorded: recorded,
    );
  }

  String ago(Duration duration) =>
      DateTime.now().toUtc().subtract(duration).toIso8601String();

  group('recent activity', () {
    testWidgets('See All opens the All Activities screen callback', (
      WidgetTester tester,
    ) async {
      bool opened = false;
      await pumpView(
        tester,
        repository((_) async => sellerDashboardResponse()),
        activityRepository: activityRepository(
          (_) async => sellerActivityResponse(),
        ),
        onSeeAllActivities: () => opened = true,
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('See All'));
      await tester.tap(find.text('See All'));
      await tester.pumpAndSettle();

      expect(opened, isTrue);
    });

    testWidgets('renders at most five events, newest first, with timestamps', (
      WidgetTester tester,
    ) async {
      final List<Map<String, dynamic>> activities = <Map<String, dynamic>>[
        for (int index = 1; index <= 6; index++)
          sellerActivityJson(
            id: index,
            action: 'inquiry_created',
            label: 'Inquiry $index',
            createdAt: ago(Duration(hours: index)),
          ),
      ];

      await pumpView(
        tester,
        repository((_) async => sellerDashboardResponse()),
        activityRepository: activityRepository(
          (_) async => sellerActivityResponse(activities: activities),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recent Activity'), findsOneWidget);
      expect(find.text('Inquiry 1'), findsOneWidget);
      expect(find.text('Inquiry 5'), findsOneWidget);
      expect(find.text('Inquiry 6'), findsNothing, reason: 'capped at five');
      expect(find.text('1 hour ago'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Inquiry 1')).dy,
        lessThan(tester.getTopLeft(find.text('Inquiry 2')).dy),
      );
    });

    testWidgets('shows loading, then the ready rows', (
      WidgetTester tester,
    ) async {
      final Completer<http.Response> pending = Completer<http.Response>();
      await pumpView(
        tester,
        repository((_) async => sellerDashboardResponse()),
        activityRepository: activityRepository((_) => pending.future),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      pending.complete(
        sellerActivityResponse(
          activities: <Map<String, dynamic>>[
            sellerActivityJson(label: 'Offer accepted'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Offer accepted'), findsOneWidget);
    });

    testWidgets('shows the empty and error states, with retry', (
      WidgetTester tester,
    ) async {
      int calls = 0;
      await pumpView(
        tester,
        repository((_) async => sellerDashboardResponse()),
        activityRepository: activityRepository((_) async {
          calls++;
          if (calls == 1) {
            return sellerActivityResponse(statusCode: 500);
          }
          return sellerActivityResponse();
        }),
      );
      await tester.pumpAndSettle();

      expect(find.text('Something went wrong on the server.'), findsOneWidget);
      await tester.ensureVisible(find.text('Retry'));
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('No recent activity yet.'), findsOneWidget);
    });

    testWidgets('renders a context-less event from the real response shape', (
      WidgetTester tester,
    ) async {
      final Map<String, dynamic> sold = sellerActivityJson(
        action: 'listing_marked_sold',
        label: 'Listing marked as sold',
        buyerId: null,
        offerId: null,
        transactionId: null,
        inquiryId: null,
      );
      sold['context'] = <String, dynamic>{};

      await pumpView(
        tester,
        repository((_) async => sellerDashboardResponse()),
        activityRepository: activityRepository(
          (_) async => sellerActivityResponse(
            activities: <Map<String, dynamic>>[sold],
          ),
        ),
        onOpenListings: () {},
      );
      await tester.pumpAndSettle();

      expect(find.text('Listing marked as sold'), findsOneWidget);
      expect(find.textContaining('unexpected response shape'), findsNothing);
    });

    testWidgets('navigates each event to its existing destination', (
      WidgetTester tester,
    ) async {
      bool openedInquiries = false;
      bool openedListings = false;
      int? offerBuyer;
      int? offerTransaction;
      int? transactionId;

      await pumpView(
        tester,
        repository((_) async => sellerDashboardResponse()),
        activityRepository: activityRepository(
          (_) async => sellerActivityResponse(
            activities: <Map<String, dynamic>>[
              sellerActivityJson(
                action: 'inquiry_created',
                label: 'Inquiry created',
              ),
              sellerActivityJson(
                id: 2,
                action: 'offer_accepted',
                label: 'Offer accepted',
                buyerId: 7,
                transactionId: 31,
              ),
              sellerActivityJson(
                id: 3,
                action: 'listing_approved',
                label: 'Listing approved',
              ),
              sellerActivityJson(
                id: 4,
                action: 'transaction_cancelled',
                label: 'Transaction cancelled',
                buyerId: null,
                offerId: null,
                transactionId: 42,
              ),
            ],
          ),
        ),
        onOpenInquiries: () => openedInquiries = true,
        onOpenListings: () => openedListings = true,
        onOpenOffer: (int buyerId, int? id) {
          offerBuyer = buyerId;
          offerTransaction = id;
        },
        onOpenTransaction: (int id) => transactionId = id,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Inquiry created'));
      await tester.tap(find.text('Offer accepted'));
      await tester.tap(find.text('Listing approved'));
      await tester.tap(find.text('Transaction cancelled'));
      await tester.pumpAndSettle();

      expect(openedInquiries, isTrue);
      expect(openedListings, isTrue);
      expect(offerBuyer, 7);
      expect(offerTransaction, 31);
      expect(transactionId, 42);
    });

    testWidgets('an offer without a buyer id falls back to the inbox', (
      WidgetTester tester,
    ) async {
      bool openedInquiries = false;
      await pumpView(
        tester,
        repository((_) async => sellerDashboardResponse()),
        activityRepository: activityRepository(
          (_) async => sellerActivityResponse(
            activities: <Map<String, dynamic>>[
              sellerActivityJson(
                action: 'offer_declined',
                label: 'Offer declined',
                buyerId: null,
              ),
            ],
          ),
        ),
        onOpenInquiries: () => openedInquiries = true,
        onOpenOffer: (_, _) => fail('no buyer id, so no direct chat'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Offer declined'));
      await tester.pumpAndSettle();

      expect(openedInquiries, isTrue);
    });

    testWidgets('pull-to-refresh re-queries once and rebuilds do not', (
      WidgetTester tester,
    ) async {
      await pumpView(
        tester,
        repository((_) async => sellerDashboardResponse()),
        activityRepository: activityRepository(
          (_) async => sellerActivityResponse(),
        ),
      );
      await tester.pumpAndSettle();

      int count() => recorded
          .where((RecordedRequest r) => r.apiPath == '/seller/activities')
          .length;
      expect(count(), 1);

      await tester.pump();
      expect(count(), 1, reason: 'rebuilds must not re-request');

      final Future<void> refresh = tester
          .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
          .show();
      await tester.pump();
      await tester.pumpAndSettle();
      await refresh;

      expect(count(), 2);
      expect(
        recorded
            .where((RecordedRequest r) => r.apiPath == '/seller/activities')
            .first
            .query,
        <String, String>{'limit': '5'},
      );
    });
  });
}
