import '../core/constants/api_constants.dart';
import '../models/inquiry.dart';
import '../models/received_inquiry_page.dart';
import '../services/inquiry_service.dart';

/// Orchestration for inquiries.
///
/// Thin, like `SellerVerificationRepository`: the transport is already behind
/// [InquiryService]. The one policy that belongs here is the seller inbox page
/// size: the server caps `per_page` at 50 with a `422`, and that limit is a
/// fact about the API rather than about any screen. Clamping it here means no
/// widget can discover the cap by provoking an error.
///
/// No error translation either: a `409` (listing not open to inquiries), a
/// `403` (not an approved seller) and a `422` (a malformed field) carry meaning
/// of their own, and rewriting them here would be a second place for wording to
/// drift. The controller branches on error kind instead.
class InquiryRepository {
  const InquiryRepository(this._service);

  final InquiryService _service;

  /// Fetches one page of the authenticated seller's received inquiries.
  ///
  /// [perPage] is clamped to `1..[SellerInquiryEndpoints.maxPerPage]`.
  Future<ReceivedInquiryPage> listReceived({int page = 1, int? perPage}) {
    return _service.listReceived(
      // A page below 1 is meaningless to Laravel, which treats it as page 1.
      page: page < 1 ? 1 : page,
      perPage: _clampPerPage(perPage),
    );
  }

  /// The inquiry the authenticated buyer already sent about [listingId], or
  /// `null` when they have not sent one.
  ///
  /// Buyer scoping is the token, so the only parameter is the listing. An
  /// inquiry in any status counts: the one-per-listing rule does not reset when
  /// an administrator closes a record.
  Future<Inquiry?> findExistingForListing(int listingId) {
    return _service.findExistingForListing(listingId);
  }

  /// Sends an inquiry and returns the created record - the server's own copy,
  /// which is what the confirmation screen shows.
  Future<Inquiry> create({
    required int listingId,
    required String message,
    required InquiryCollectionDateOption collectionDateOption,
    DateTime? preferredSchedule,
    String? subject,
    bool? purchaseInterest,
    InquiryTransactionMethod? transactionMethod,
    InquiryDeliveryMethod? deliveryMethod,
    String? deliveryFee,
    InquiryContactMethod? contactMethod,
    InquiryPaymentMethod? paymentMethod,
    InquiryCollectionMethod? collectionMethod,
  }) {
    return _service.create(
      listingId: listingId,
      message: message,
      collectionDateOption: collectionDateOption,
      preferredSchedule: preferredSchedule,
      subject: subject,
      purchaseInterest: purchaseInterest,
      transactionMethod: transactionMethod,
      deliveryMethod: deliveryMethod,
      deliveryFee: deliveryFee,
      contactMethod: contactMethod,
      paymentMethod: paymentMethod,
      collectionMethod: collectionMethod,
    );
  }

  static int _clampPerPage(int? perPage) {
    final int requested = perPage ?? SellerInquiryEndpoints.defaultPerPage;
    if (requested < 1) {
      return 1;
    }
    if (requested > SellerInquiryEndpoints.maxPerPage) {
      return SellerInquiryEndpoints.maxPerPage;
    }
    return requested;
  }
}
