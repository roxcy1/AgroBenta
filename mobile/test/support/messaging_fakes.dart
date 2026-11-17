import 'dart:convert';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/repositories/messaging_repository.dart';
import 'package:agrobenta_mobile/services/messaging_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'auth_fakes.dart';

/// A `MessageResource` payload exactly as the backend serialises one.
///
/// Field names and value spellings are copied from
/// `backend/app/Http/Resources/MessageResource.php`; a test that passes against
/// this fixture is asserting against the real contract.
Map<String, dynamic> messageJson({
  Object? id = 1,
  String body = 'Is this still available?',
  Object? senderId = 7,
  Object? receiverId = 3,
  Object? listingId = 12,
  bool read = false,
  Object? readAt,
  Object? createdAt = '2026-10-01T08:15:00.000000Z',
  Map<String, dynamic>? sender,
  Map<String, dynamic>? receiver,
  Map<String, dynamic>? inquiry,
}) {
  return <String, dynamic>{
    'id': id,
    'body': body,
    'sender_id': senderId,
    'receiver_id': receiverId,
    'listing_id': listingId,
    'read': read,
    'read_at': readAt,
    'created_at': createdAt,
    'sender': sender ?? chatUserJson(id: senderId, name: 'Ana Reyes'),
    'receiver': receiver ?? chatUserJson(id: receiverId, name: 'Rizal Farms'),
    'inquiry': inquiry,
  };
}

/// The `inquiry` card payload `MessageResource` attaches to the opener.
Map<String, dynamic> inquiryCardJson({
  Object? id = 55,
  int requestedQuantity = 1,
  Object? listingId = 12,
  String title = 'Holstein Heifer',
  String? askingPrice = '50000.00',
  String? photoUrl,
  String? paymentMethod = 'gcash',
  String? collectionMethod = 'farm_pickup',
  String? preferredSchedule = '2026-11-10',
  String message = 'Still available? I can pick it up.',
}) {
  return <String, dynamic>{
    'id': id,
    'requested_quantity': requestedQuantity,
    'listing': <String, dynamic>{
      'id': listingId,
      'title': title,
      'asking_price': askingPrice,
      'photo_url': photoUrl,
    },
    'payment_method': paymentMethod,
    'collection_method': collectionMethod,
    'preferred_schedule': preferredSchedule,
    'message': message,
  };
}

/// The embedded chat-user projection: `{ id, name, avatar_url }`.
Map<String, dynamic> chatUserJson({
  Object? id = 3,
  String name = 'Rizal Farms',
  Object? avatarUrl,
}) {
  return <String, dynamic>{'id': id, 'name': name, 'avatar_url': avatarUrl};
}

/// A `ConversationResource` payload exactly as the backend serialises one.
///
/// Field names and value spellings are copied from
/// `backend/app/Http/Resources/ConversationResource.php`.
Map<String, dynamic> conversationJson({
  Map<String, dynamic>? counterpart,
  Object? listingId = 12,
  String? listingTitle = 'Holstein Heifer',
  String lastMessage = 'Still available?',
  Object? lastMessageAt = '2026-10-01T08:15:00.000000Z',
  Object? unreadCount = 0,
  bool hasInquiry = false,
  bool hasTransaction = false,
  String? listingPrice,
  List<String> roles = const <String>['buyer', 'seller'],
  int listingCount = 1,
  Map<String, dynamic>? latestOffer,
  Map<String, dynamic>? eligibleInquiry,
}) {
  return <String, dynamic>{
    'counterpart': counterpart ?? chatUserJson(),
    'listing_id': listingId,
    'listing_title': listingTitle,
    'listing_price': listingPrice,
    'last_message': lastMessage,
    'last_message_at': lastMessageAt,
    'unread_count': unreadCount,
    'has_inquiry': hasInquiry,
    'has_transaction': hasTransaction,
    'roles': roles,
    'listing_count': listingCount,
    'latest_offer': latestOffer,
    'eligible_inquiry': eligibleInquiry,
  };
}

/// The `latest_offer` projection `ConversationResource` sends.
Map<String, dynamic> conversationOfferJson({
  Object? id = 41,
  String status = 'pending',
  String proposedAmount = '47500.00',
  int proposedQuantity = 1,
  Object? listingId = 12,
  String? listingTitle = 'Holstein Heifer',
}) {
  return <String, dynamic>{
    'id': id,
    'status': status,
    'proposed_amount': proposedAmount,
    'proposed_quantity': proposedQuantity,
    'listing_id': listingId,
    'listing_title': listingTitle,
  };
}

/// The `eligible_inquiry` projection `ConversationResource` sends.
Map<String, dynamic> eligibleInquiryJson({
  Object? id = 55,
  int requestedQuantity = 1,
  Object? listingId = 12,
  String? listingTitle = 'Holstein Heifer',
  String? askingPrice = '50000.00',
  int? listingAvailableQuantity = 5,
  bool listingInventoryReconciliationRequired = false,
  String? listingPhotoUrl,
  String? paymentMethod = 'gcash',
  String? collectionMethod = 'farm_pickup',
  String? preferredSchedule = '2026-11-10',
}) {
  return <String, dynamic>{
    'id': id,
    'requested_quantity': requestedQuantity,
    'listing_id': listingId,
    'listing_title': listingTitle,
    'asking_price': askingPrice,
    'listing_available_quantity': listingAvailableQuantity,
    'listing_inventory_reconciliation_required': listingInventoryReconciliationRequired,
    'listing_photo_url': listingPhotoUrl,
    'payment_method': paymentMethod,
    'collection_method': collectionMethod,
    'preferred_schedule': preferredSchedule,
  };
}

const Map<String, String> _jsonHeaders = <String, String>{
  'content-type': 'application/json',
};

/// A successful `GET /api/conversations/{id}/messages`.
http.Response messageThreadResponse({
  List<Map<String, dynamic>>? messages,
  int statusCode = 200,
}) {
  final List<Map<String, dynamic>> list = messages ?? <Map<String, dynamic>>[];
  return http.Response(
    jsonEncode(
      successEnvelope(
        data: <String, dynamic>{
          'messages': messages ?? <Map<String, dynamic>>[],
          'pagination': <String, dynamic>{
            'current_page': 1,
            'last_page': 1,
            'per_page': 30,
            'total': list.length,
          },
        },
      ),
    ),
    statusCode,
    headers: _jsonHeaders,
  );
}

/// A successful `POST /conversations/{id}/read`.
http.Response threadReadResponse({int updated = 0, int statusCode = 200}) {
  return http.Response(
    jsonEncode(successEnvelope(data: <String, dynamic>{'updated': updated})),
    statusCode,
    headers: _jsonHeaders,
  );
}

/// A successful `GET /conversations` inbox.
http.Response conversationsResponse({
  List<Map<String, dynamic>>? conversations,
  int statusCode = 200,
}) {
  return http.Response(
    jsonEncode(
      successEnvelope(
        data: <String, dynamic>{
          'conversations': conversations ?? <Map<String, dynamic>>[],
        },
      ),
    ),
    statusCode,
    headers: _jsonHeaders,
  );
}

/// The messaging stack over a mock transport, built through the same
/// [ApiClient] the app uses so envelope unwrapping and the bearer token are
/// exercised as production does.
MessagingRepository buildMessagingRepository(
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
  return MessagingRepository(MessagingService(client));
}
