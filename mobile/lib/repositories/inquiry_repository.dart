import '../models/inquiry.dart';
import '../services/inquiry_service.dart';

/// Orchestration for inquiries.
///
/// Thin, like `SellerVerificationRepository`: the transport is already behind
/// [InquiryService] and there is no lifetime or ordering policy to arbitrate
/// for a single create call.
///
/// No error translation either: a `409` (listing not open to inquiries) and a
/// `422` (a malformed field) carry meaning of their own, and rewriting them
/// here would be a second place for wording to drift. The controller branches
/// on [ApiErrorKind] instead.
class InquiryRepository {
  const InquiryRepository(this._service);

  final InquiryService _service;

  /// Sends an inquiry and returns the created record — the server's own copy,
  /// which is what the confirmation screen shows.
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
    return _service.create(
      listingId: listingId,
      message: message,
      subject: subject,
      purchaseInterest: purchaseInterest,
      transactionMethod: transactionMethod,
      deliveryMethod: deliveryMethod,
      deliveryFee: deliveryFee,
      contactMethod: contactMethod,
      preferredSchedule: preferredSchedule,
    );
  }
}
