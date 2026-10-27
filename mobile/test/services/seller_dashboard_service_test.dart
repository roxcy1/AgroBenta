import 'package:agrobenta_mobile/core/constants/api_constants.dart';
import 'package:agrobenta_mobile/models/seller_dashboard.dart';
import 'package:agrobenta_mobile/services/seller_dashboard_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../support/auth_fakes.dart';
import '../support/seller_dashboard_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;
  late SellerDashboardService service;

  SellerDashboardService build(
    Future<http.Response> Function(RecordedRequest request) handler,
  ) => buildSellerDashboardService(tokenStore, handler, recorded: recorded);

  setUp(() {
    tokenStore = FakeTokenStore('1|mobile-token');
    recorded = <RecordedRequest>[];
    service = build((_) async => sellerDashboardResponse());
  });

  test('GETs the dashboard path with the bearer token and no query', () async {
    await service.load();

    expect(recorded, hasLength(1));
    expect(recorded.single.method, 'GET');
    expect(recorded.single.apiPath, SellerDashboardEndpoints.summary);
    expect(recorded.single.authorization, 'Bearer 1|mobile-token');
    expect(recorded.single.query, isEmpty);
  });

  test('returns the parsed counts', () async {
    final SellerDashboard dashboard = await service.load();

    expect(dashboard.listings.total, 6);
    expect(dashboard.inquiries.total, 3);
    expect(dashboard.transactions.total, 4);
    expect(dashboard.transactions.pending, 2);
  });
}
