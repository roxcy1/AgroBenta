import '../models/inquiry.dart';
import '../models/offer.dart';
import '../services/offer_service.dart';

/// Orchestration for purchase offers.
///
/// Thin by design, mirroring `InquiryRepository`. The offer list is not
/// paginated, so there is no page-size policy to own here. Error translation is
/// deliberately **not** done here: `ApiException.message` is already curated to
/// be displayable, so a second translation layer would be a second place for
/// wording to drift.
class OfferRepository {
  const OfferRepository(this._service);

  final OfferService _service;

  /// The caller's offers, optionally narrowed by inquiry, listing,
  /// counterpart or status.
  Future<List<Offer>> list({
    int? inquiryId,
    int? listingId,
    int? counterpartId,
    OfferStatus? status,
  }) {
    return _service.list(
      inquiryId: inquiryId,
      listingId: listingId,
      counterpartId: counterpartId,
      status: status,
    );
  }

  /// Creates a purchase offer as the authenticated seller.
  Future<Offer> create({
    required int inquiryId,
    required int listingId,
    required String proposedAmount,
    DateTime? proposedPickupDate,
    InquiryPaymentMethod? paymentMethod,
    InquiryCollectionMethod? collectionMethod,
    String? note,
  }) {
    return _service.create(
      inquiryId: inquiryId,
      listingId: listingId,
      proposedAmount: proposedAmount,
      proposedPickupDate: proposedPickupDate,
      paymentMethod: paymentMethod,
      collectionMethod: collectionMethod,
      note: note,
    );
  }

  /// Accepts a pending offer as the buyer, creating one transaction.
  Future<OfferAcceptance> accept(int id) => _service.accept(id);

  /// Declines a pending offer as the buyer.
  Future<Offer> decline(int id) => _service.decline(id);

  /// Withdraws a pending offer as the seller who made it.
  Future<Offer> withdraw(int id) => _service.withdraw(id);
}
