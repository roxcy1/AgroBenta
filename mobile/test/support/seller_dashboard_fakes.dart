import 'dart:convert';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/features/seller_dashboard/state/seller_dashboard_controller.dart';
import 'package:agrobenta_mobile/repositories/seller_activity_repository.dart';
import 'package:agrobenta_mobile/repositories/seller_dashboard_repository.dart';
import 'package:agrobenta_mobile/services/seller_activity_service.dart';
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
  int completedTransactions = 1,
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
      'completed': completedTransactions,
    },
  };
}

/// One `SellerActivityResource` payload.
Map<String, dynamic> sellerActivityJson({
  Object? id = 1,
  String action = 'offer_accepted',
  String label = 'Offer accepted',
  String? description = 'Offer #21 accepted; transaction #31 created.',
  Object? createdAt = '2026-11-03T10:00:00.000000Z',
  String? targetType = 'offer',
  Object? targetId = 21,
  Object? listingId = 4,
  Object? buyerId = 7,
  Object? offerId = 21,
  Object? transactionId = 31,
  Object? inquiryId,
}) {
  return <String, dynamic>{
    'id': id,
    'action': action,
    'label': label,
    'description': description,
    'created_at': createdAt,
    'target_type': targetType,
    'target_id': targetId,
    'context': <String, dynamic>{
      'listing_id': listingId,
      'buyer_id': buyerId,
      'offer_id': offerId,
      'transaction_id': transactionId,
      'inquiry_id': inquiryId,
    },
  };
}

/// A successful `GET /seller/activities`.
http.Response sellerActivityResponse({
  List<Map<String, dynamic>>? activities,
  int statusCode = 200,
  int currentPage = 1,
  int lastPage = 1,
  int perPage = 5,
  int? total,
}) {
  final List<Map<String, dynamic>> rows =
      activities ?? <Map<String, dynamic>>[];
  return http.Response(
    jsonEncode(
      successEnvelope(
        data: <String, dynamic>{
          'activities': rows,
          'pagination': <String, dynamic>{
            'current_page': currentPage,
            'last_page': lastPage,
            'per_page': perPage,
            'total': total ?? rows.length,
          },
        },
      ),
    ),
    statusCode,
    headers: _jsonHeaders,
  );
}

/// The activity stack over a mock transport, for service/repository tests.
SellerActivityRepository buildSellerActivityRepository(
  FakeTokenStore tokenStore,
  Future<http.Response> Function(RecordedRequest request) handler, {
  List<RecordedRequest>? recorded,
}) {
  return SellerActivityRepository(
    SellerActivityService(
      ApiClient(
        tokenStorage: tokenStore,
        httpClient: MockClient((http.Request request) async {
          final RecordedRequest entry = RecordedRequest(request);
          recorded?.add(entry);
          return handler(entry);
        }),
      ),
    ),
  );
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
