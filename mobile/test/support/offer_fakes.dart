import 'dart:convert';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/features/offers/state/chat_offers_controller.dart';
import 'package:agrobenta_mobile/features/offers/state/make_offer_controller.dart';
import 'package:agrobenta_mobile/repositories/offer_repository.dart';
import 'package:agrobenta_mobile/services/offer_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'auth_fakes.dart';
import 'transaction_fakes.dart';

/// An `OfferResource` payload exactly as the backend serialises one.
///
/// Field names, nullability and value spellings are copied from
/// `backend/app/Http/Resources/OfferResource.php`. `proposed_amount` is a
/// decimal **string**, like every other money field in the app.
Map<String, dynamic> offerJson({
  Object? id = 1,
  Object? inquiryId = 5,
  Object? listingId = 12,
  Object? sellerId = 3,
  Object? buyerId = 7,
  Object? proposedAmount = '48000.00',
  Object? proposedPickupDate,
  String? paymentMethod,
  String? collectionMethod,
  String? note,
  Map<String, dynamic>? originalTerms,
  String status = 'pending',
  Object? respondedAt,
  Object? createdAt = '2026-10-30T08:15:00.000000Z',
}) {
  return <String, dynamic>{
    'id': id,
    'inquiry_id': inquiryId,
    'listing_id': listingId,
    'seller_id': sellerId,
    'buyer_id': buyerId,
    'proposed_amount': proposedAmount,
    'proposed_pickup_date': proposedPickupDate,
    'payment_method': paymentMethod,
    'collection_method': collectionMethod,
    'note': note,
    'original_terms': originalTerms,
    'status': status,
    'responded_at': respondedAt,
    'created_at': createdAt,
  };
}

const Map<String, String> _jsonHeaders = <String, String>{
  'content-type': 'application/json',
};

/// The `200` that `GET /api/offers` answers with. The list is not paginated.
http.Response offersResponse({List<Map<String, dynamic>>? offers}) {
  return http.Response(
    jsonEncode(
      successEnvelope(
        data: <String, dynamic>{
          'offers': offers ?? <Map<String, dynamic>>[offerJson()],
        },
      ),
    ),
    200,
    headers: _jsonHeaders,
  );
}

/// The `201` that `POST /api/offers` answers with.
http.Response offerCreatedResponse({Map<String, dynamic>? offer}) {
  return http.Response(
    jsonEncode(
      successEnvelope(message: 'Offer sent.', data: offer ?? offerJson()),
    ),
    201,
    headers: _jsonHeaders,
  );
}

/// The `200` that `POST /api/offers/{id}/accept` answers with: the accepted
/// offer plus the transaction the acceptance created.
http.Response offerAcceptedResponse({
  Map<String, dynamic>? offer,
  Map<String, dynamic>? transaction,
}) {
  return http.Response(
    jsonEncode(
      successEnvelope(
        data: <String, dynamic>{
          'offer': offer ?? offerJson(status: 'accepted'),
          'transaction':
              transaction ?? transactionJson(totalAmount: '48000.00'),
        },
      ),
    ),
    200,
    headers: _jsonHeaders,
  );
}

/// The `200` that a successful decline or withdraw answers with.
http.Response offerUpdatedResponse({Map<String, dynamic>? offer}) {
  return http.Response(
    jsonEncode(successEnvelope(data: offer ?? offerJson())),
    200,
    headers: _jsonHeaders,
  );
}

/// A `409` for an offer that already left `pending`.
http.Response offerConflictResponse({
  String message = 'This offer has already been responded to.',
}) {
  return http.Response(
    jsonEncode(<String, String>{'message': message}),
    409,
    headers: _jsonHeaders,
  );
}

/// A `422` for a body the server refuses.
http.Response offerValidationResponse({
  Map<String, Object> errors = const <String, Object>{
    'proposed_amount': <String>['The proposed amount must be at least 0.01.'],
  },
}) {
  return http.Response(
    jsonEncode(validationErrorBody(errors: errors)),
    422,
    headers: _jsonHeaders,
  );
}

/// The offer service over a mock transport — the layer that owns the request
/// allow-lists, so a request-shape test drives this.
OfferService buildOfferService(
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
  return OfferService(client);
}

/// The repository over a mock transport, through the real [ApiClient].
OfferRepository buildOfferRepository(
  FakeTokenStore tokenStore,
  Future<http.Response> Function(RecordedRequest request) handler, {
  List<RecordedRequest>? recorded,
}) {
  return OfferRepository(
    buildOfferService(tokenStore, handler, recorded: recorded),
  );
}

/// The per-chat offers controller over a mock transport.
ChatOffersController buildChatOffersController(
  FakeTokenStore tokenStore,
  Future<http.Response> Function(RecordedRequest request) handler, {
  int counterpartId = 3,
  List<RecordedRequest>? recorded,
}) {
  return ChatOffersController(
    buildOfferRepository(tokenStore, handler, recorded: recorded),
    counterpartId: counterpartId,
  );
}

/// The make-offer controller over a mock transport.
MakeOfferController buildMakeOfferController(
  FakeTokenStore tokenStore,
  Future<http.Response> Function(RecordedRequest request) handler, {
  List<RecordedRequest>? recorded,
}) {
  return MakeOfferController(
    buildOfferRepository(tokenStore, handler, recorded: recorded),
  );
}
