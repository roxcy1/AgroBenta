import '../core/utils/json_utils.dart';
import 'transaction.dart';

/// The lifecycle state of a purchase offer, as stored in `offers.status`.
///
/// Serialised by `backend/app/Enums/OfferStatus.php` and surfaced verbatim by
/// `OfferResource`. `pending` is the only actionable state: the buyer may
/// accept or decline, and the seller may withdraw. Every other state is
/// terminal. `expired` is modelled for fidelity even though no current backend
/// path produces it.
enum OfferStatus {
  pending('pending'),
  accepted('accepted'),
  declined('declined'),
  withdrawn('withdrawn'),
  expired('expired');

  const OfferStatus(this.value);

  /// The exact lowercase string the API sends.
  final String value;

  /// The display label for the offer badge. Display-only; the API contract is
  /// always [value].
  String get label => switch (this) {
    OfferStatus.pending => 'Pending',
    OfferStatus.accepted => 'Accepted',
    OfferStatus.declined => 'Declined',
    OfferStatus.withdrawn => 'Withdrawn',
    OfferStatus.expired => 'Expired',
  };

  /// Whether this offer can still be accepted, declined or withdrawn.
  bool get isPending => this == OfferStatus.pending;

  /// Parses the API value, failing loudly on an unknown one.
  static OfferStatus fromValue(String value) {
    for (final OfferStatus status in OfferStatus.values) {
      if (status.value == value) {
        return status;
      }
    }
    throw FormatException('Unknown offer status "$value".');
  }
}

/// One purchase offer a seller made to a buyer inside a conversation.
///
/// Mirrors `backend/app/Http/Resources/OfferResource.php` field for field.
/// `proposed_amount` stays a decimal [String], like every other money field in
/// this app, and is formatted only at the display edge. The buyer sees the
/// seller's proposed price; the seller sees the offer they made.
class Offer {
  const Offer({
    required this.id,
    required this.inquiryId,
    required this.listingId,
    required this.sellerId,
    required this.buyerId,
    required this.proposedAmount,
    required this.status,
    required this.respondedAt,
    required this.createdAt,
  });

  factory Offer.fromJson(Map<String, dynamic> json) {
    return Offer(
      id: readInt(json, 'id'),
      inquiryId: readInt(json, 'inquiry_id'),
      listingId: readInt(json, 'listing_id'),
      sellerId: readInt(json, 'seller_id'),
      buyerId: readInt(json, 'buyer_id'),
      proposedAmount: readDecimalString(json, 'proposed_amount'),
      status: OfferStatus.fromValue(readString(json, 'status')),
      respondedAt: readNullableDateTime(json, 'responded_at'),
      createdAt: readNullableDateTime(json, 'created_at'),
    );
  }

  /// `offers.id`.
  final int id;

  /// The inquiry this offer answers. An offer is tied to one inquiry, hence
  /// one listing.
  final int inquiryId;

  /// The listing the inquiry is about.
  final int listingId;

  /// The seller who made the offer.
  final int sellerId;

  /// The buyer who may accept or decline it.
  final int buyerId;

  /// The seller's proposed final price, as the API sent it, e.g. `"12500.00"`.
  ///
  /// Never computed on the client: it is the agreed price once accepted and is
  /// stored independently of the listing's asking price.
  final String proposedAmount;

  final OfferStatus status;

  /// When the buyer responded, or `null` while the offer is pending.
  final DateTime? respondedAt;

  final DateTime? createdAt;

  /// Whether [userId] is the buyer this offer was made to.
  bool isBuyer(int userId) => buyerId == userId;

  /// Whether [userId] is the seller who made this offer.
  bool isSeller(int userId) => sellerId == userId;

  @override
  String toString() => 'Offer($id, ${status.value}, $proposedAmount)';
}

/// The result of accepting an offer: the accepted offer and the transaction
/// the acceptance created.
///
/// `OfferController@accept` returns both in `data`, so the client can show the
/// new transaction without a second request. This wrapper exists so a caller
/// cannot accidentally treat the response as a bare offer.
class OfferAcceptance {
  const OfferAcceptance({required this.offer, required this.transaction});

  factory OfferAcceptance.fromJson(Map<String, dynamic> json) {
    return OfferAcceptance(
      offer: Offer.fromJson(readObject(json, 'offer')),
      transaction: Transaction.fromJson(readObject(json, 'transaction')),
    );
  }

  final Offer offer;

  /// The `pending` transaction created by the acceptance. Its
  /// `total_amount` is the offer's `proposed_amount`, server-derived.
  final Transaction transaction;
}
