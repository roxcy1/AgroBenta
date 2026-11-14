import '../core/constants/api_constants.dart';
import '../core/network/api_client.dart';
import '../models/inquiry.dart';
import '../models/offer.dart';

/// The purchase-offer API surface.
///
/// One method per implemented endpoint, and nothing else. No token handling, no
/// persistence, no error translation beyond what [ApiClient] already does —
/// those belong to `OfferRepository`.
///
/// There is deliberately **no `expire` method**: no backend path produces an
/// expired offer, so the client cannot ask for one.
class OfferService {
  const OfferService(this._apiClient);

  final ApiClient _apiClient;

  /// `GET /offers` — the caller's offers, newest first.
  ///
  /// Every filter narrows a list that is already scoped to the token. The
  /// query is built from an explicit allow-list, so a field added to [Offer]
  /// can never silently become a filter.
  Future<List<Offer>> list({
    int? inquiryId,
    int? listingId,
    int? counterpartId,
    OfferStatus? status,
  }) {
    final Map<String, dynamic> query = <String, dynamic>{};
    if (inquiryId != null) {
      query['inquiry_id'] = inquiryId;
    }
    if (listingId != null) {
      query['listing_id'] = listingId;
    }
    if (counterpartId != null) {
      query['counterpart_id'] = counterpartId;
    }
    if (status != null) {
      query['status'] = status.value;
    }

    return _apiClient.get<List<Offer>>(
      OfferEndpoints.list,
      query: query,
      parse: (Object? data) {
        final Map<String, dynamic> map = _asObject(data, 'GET /offers');
        final List<dynamic> raw =
            (map['offers'] as List<dynamic>?) ?? const <dynamic>[];
        return raw
            .whereType<Map<String, dynamic>>()
            .map(Offer.fromJson)
            .toList(growable: false);
      },
    );
  }

  /// `POST /offers` — create a purchase offer as the listing's seller.
  ///
  /// The body is exactly `{ inquiry_id, listing_id, proposed_amount }`. The
  /// seller is the token, the buyer is derived from the inquiry, and a new
  /// offer is always `pending`, so those values are unreachable from here.
  Future<Offer> create({
    required int inquiryId,
    required int listingId,
    required String proposedAmount,
    int proposedQuantity = 1,
    DateTime? proposedPickupDate,
    InquiryPaymentMethod? paymentMethod,
    InquiryCollectionMethod? collectionMethod,
    String? note,
  }) {
    final Map<String, dynamic> body = <String, dynamic>{
      'inquiry_id': inquiryId,
      'listing_id': listingId,
      'proposed_amount': proposedAmount,
      'proposed_quantity': proposedQuantity,
    };
    if (proposedPickupDate != null) {
      body['proposed_pickup_date'] = _isoDate(proposedPickupDate);
    }
    if (paymentMethod != null) {
      body['payment_method'] = paymentMethod.value;
    }
    if (collectionMethod != null) {
      body['collection_method'] = collectionMethod.value;
    }
    if (note != null && note.trim().isNotEmpty) {
      body['note'] = note.trim();
    }

    return _apiClient.post<Offer>(
      OfferEndpoints.create,
      body: body,
      parse: (Object? data) => Offer.fromJson(_asObject(data, 'POST /offers')),
    );
  }

  /// `yyyy-MM-dd` — the date-only shape the API validates.
  static String _isoDate(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-$month-$day';
  }

  /// `POST /offers/{id}/accept` — the buyer accepts, creating a transaction.
  ///
  /// Returns both the accepted offer and the transaction the acceptance
  /// created. The body allow-list is empty: the action reads no input.
  Future<OfferAcceptance> accept(int id) {
    return _apiClient.post<OfferAcceptance>(
      OfferEndpoints.accept(id),
      parse: (Object? data) =>
          OfferAcceptance.fromJson(_asObject(data, 'POST /offers/$id/accept')),
    );
  }

  /// `POST /offers/{id}/decline` — the buyer declines a pending offer.
  ///
  /// The body allow-list is empty. A `409` means the offer already left
  /// `pending`.
  Future<Offer> decline(int id) {
    return _apiClient.post<Offer>(
      OfferEndpoints.decline(id),
      parse: (Object? data) =>
          Offer.fromJson(_asObject(data, 'POST /offers/$id/decline')),
    );
  }

  /// `POST /offers/{id}/withdraw` — the creating seller withdraws an offer.
  ///
  /// The body allow-list is empty. A `409` means the offer already left
  /// `pending`.
  Future<Offer> withdraw(int id) {
    return _apiClient.post<Offer>(
      OfferEndpoints.withdraw(id),
      parse: (Object? data) =>
          Offer.fromJson(_asObject(data, 'POST /offers/$id/withdraw')),
    );
  }

  /// Casts an unwrapped `data` payload to a JSON object with a message that
  /// names the endpoint, instead of a bare cast error. A `FormatException`
  /// here is translated by `ApiClient` into `malformedResponse`.
  static Map<String, dynamic> _asObject(Object? data, String context) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return data.cast<String, dynamic>();
    }
    throw FormatException(
      'Expected the $context response data to be a JSON object, got '
      '${data.runtimeType}.',
    );
  }
}
