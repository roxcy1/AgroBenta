import '../core/constants/api_constants.dart';
import '../models/inquiry.dart';
import '../models/inquiry_list_item.dart';
import '../services/inquiry_service.dart';

/// Orchestration for inquiries.
///
/// Thin, like `SellerVerificationRepository`: the transport is already behind
/// [InquiryService].
///
/// No error translation either: a `409` (listing not open to inquiries), a
/// `403` (not an approved seller) and a `422` (a malformed field) carry meaning
/// of their own, and rewriting them here would be a second place for wording to
/// drift. The controller branches on error kind instead.
class InquiryRepository {
  const InquiryRepository(this._service);

  final InquiryService _service;

  /// Fetches the caller's active inquiries on one side.
  Future<List<InquiryListItem>> listActive({String? role}) {
    return _service.listActive(role: role);
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

}
