import '../core/constants/api_constants.dart';
import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../models/inquiry.dart';
import '../models/received_inquiry_page.dart';

/// The inquiry API surface: the buyer's create path and the seller's inbox.
///
/// No token handling, no persistence, no error translation - those belong to
/// `InquiryRepository` and `ApiClient`.
///
/// ## What this service can and cannot send
///
/// [create] builds its body from an explicit allow-list — exactly the fields
/// `StoreInquiryRequest` validates ([InquiryEndpoints.writableFields]).
/// `buyer_id`, `seller_id` and `status` are not merely unused, they are
/// **unreachable**: there is no parameter on this method that could become one
/// of those keys. The buyer is the token, the seller is the listing's owner,
/// and the status is `open` by construction, all server-side
/// (functional documentation §10.1).
///
/// Blank optional values are omitted rather than sent empty: `""` is not the
/// same thing as "not provided" when a human later reads the record, and the
/// server treats an absent key and an explicit `null` identically.
class InquiryService {
  const InquiryService(this._apiClient);

  final ApiClient _apiClient;

  /// `GET /seller/inquiries` — one page of the authenticated seller's inbox.
  ///
  /// [page] and [perPage] are the entire query allow-list;
  /// `IndexSellerInquiryRequest` refuses `buyer_id`, `seller_id` and `status`.
  /// The seller scope is the token, so there is no id to send.
  Future<ReceivedInquiryPage> listReceived({
    int page = 1,
    int perPage = SellerInquiryEndpoints.defaultPerPage,
  }) {
    return _apiClient.get<ReceivedInquiryPage>(
      SellerInquiryEndpoints.received,
      query: <String, dynamic>{
        // Explicit allow-list. Anything not named here has no path to the
        // request, so a field added to the model can never become a filter.
        'page': page,
        'per_page': perPage,
      },
      parse: (Object? data) => ReceivedInquiryPage.fromJson(
        _asObject(data, 'GET /seller/inquiries'),
      ),
    );
  }

  /// `POST /inquiries` — send an inquiry about [listingId].
  ///
  /// Throws [ApiException]:
  ///  * [ApiErrorKind.conflict] on a `409` — the listing is not active, or it
  ///    is the caller's own. Not a validation problem; retrying cannot help
  ///    until the listing's state changes, so the screen must not present it
  ///    as one.
  ///  * [ApiErrorKind.notFound] on a `404` — the listing no longer exists.
  ///  * [ApiErrorKind.validation] on a `422`, carrying per-field messages.
  ///  * [ApiErrorKind.unauthorized] on a `401`; the token has been cleared.
  Future<Inquiry> create({
    required int listingId,
    required String message,
    String? subject,
    bool? purchaseInterest,
    InquiryTransactionMethod? transactionMethod,
    InquiryDeliveryMethod? deliveryMethod,
    String? deliveryFee,
    InquiryContactMethod? contactMethod,
    DateTime? preferredSchedule,
  }) {
    return _apiClient.post<Inquiry>(
      InquiryEndpoints.create,
      body: <String, dynamic>{
        // Explicit allow-list, in the order the contract lists them. Anything
        // a form adds later has to be named here to be sent.
        'listing_id': listingId,
        'message': message.trim(),
        if (_present(subject)) 'subject': subject!.trim(),
        'purchase_interest': ?purchaseInterest,
        if (transactionMethod != null)
          'transaction_method': transactionMethod.value,
        if (deliveryMethod != null) 'delivery_method': deliveryMethod.value,
        if (_present(deliveryFee)) 'delivery_fee': deliveryFee!.trim(),
        if (contactMethod != null) 'contact_method': contactMethod.value,
        if (preferredSchedule != null)
          'preferred_schedule': _dateOnly(preferredSchedule),
      },
      parse: (Object? data) =>
          Inquiry.fromJson(_asObject(data, 'POST /inquiries')),
    );
  }

  static bool _present(String? value) =>
      value != null && value.trim().isNotEmpty;

  /// `yyyy-MM-dd`, which is what Laravel's `date` rule and the `date` column
  /// round-trip as. A full ISO-8601 timestamp would also validate, but it
  /// carries a time the form never asked for.
  static String _dateOnly(DateTime value) {
    final String month = value.month.toString().padLeft(2, '0');
    final String day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  /// Casts an unwrapped `data` payload to a JSON object with a message that
  /// names the endpoint, instead of a bare cast error. A [FormatException] here
  /// is translated by `ApiClient` into [ApiErrorKind.malformedResponse].
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
