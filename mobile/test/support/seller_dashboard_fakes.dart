import 'dart:convert';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/features/seller_dashboard/state/seller_dashboard_controller.dart';
import 'package:agrobenta_mobile/repositories/seller_dashboard_repository.dart';
import 'package:agrobenta_mobile/services/seller_dashboard_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'auth_fakes.dart';

const Map<String, String> _jsonHeaders = <String, String>{
  'content-type': 'application/json',
};

/// The `data` payload of `GET /api/seller/dashboard`.
Map<String, dynamic> sellerDashboardJson({
  int totalListings = 6,
  int draft = 1,
  int pendingListings = 1,
  int active = 2,
  int sold = 1,
  int inactive = 1,
  int totalInquiries = 3,
  int totalTransactions = 4,
  int pendingTransactions = 2,
}) {
  return <String, dynamic>{
    'listings': <String, dynamic>{
      'total': totalListings,
      'draft': draft,
      'pending': pendingListings,
      'active': active,
      'sold': sold,
      'inactive': inactive,
    },
    'inquiries': <String, dynamic>{'total': totalInquiries},
    'transactions': <String, dynamic>{
      'total': totalTransactions,
      'pending': pendingTransactions,
    },
  };
}

http.Response sellerDashboardResponse({
  Map<String, dynamic>? dashboard,
  int statusCode = 200,
}) {
  return http.Response(
    jsonEncode(successEnvelope(data: dashboard ?? sellerDashboardJson())),
    statusCode,
    headers: _jsonHeaders,
  );
}

http.Response sellerDashboardServerErrorResponse({
  String message = 'Server error.',
}) {
  return http.Response(
    jsonEncode(<String, String>{'message': message}),
    500,
    headers: _jsonHeaders,
  );
}

SellerDashboardService buildSellerDashboardService(
  FakeTokenStore tokenStore,
  Future<http.Response> Function(RecordedRequest request) handler, {
  List<RecordedRequest>? recorded,
}) {
  final ApiClient client = ApiClient(
    tokenStorage: tokenStore,
    httpClient: MockClient((http.Request request) async {
      final RecordedRequest entry = RecordedRequest(request);
      recorded?.add(entry);
      return handler(entry);
    }),
  );
  return SellerDashboardService(client);
}

SellerDashboardRepository buildSellerDashboardRepository(
  FakeTokenStore tokenStore,
  Future<http.Response> Function(RecordedRequest request) handler, {
  List<RecordedRequest>? recorded,
}) {
  return SellerDashboardRepository(
    buildSellerDashboardService(tokenStore, handler, recorded: recorded),
  );
}

SellerDashboardController buildSellerDashboardController(
  FakeTokenStore tokenStore,
  Future<http.Response> Function(RecordedRequest request) handler, {
  List<RecordedRequest>? recorded,
}) {
  return SellerDashboardController(
    buildSellerDashboardRepository(tokenStore, handler, recorded: recorded),
  );
}
