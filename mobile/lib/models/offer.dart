import '../core/utils/json_utils.dart';
import 'inquiry.dart';
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
    this.proposedQuantity = 1,
    required this.status,
    required this.respondedAt,
    required this.createdAt,
    this.proposedPickupDate,
    this.paymentMethod,
    this.collectionMethod,
    this.note,
    this.originalPaymentMethod,
    this.originalCollectionMethod,
    this.originalPickupDate,
  });

  factory Offer.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? original = readNullableObject(
      json,
      'original_terms',
    );

    return Offer(
      id: readInt(json, 'id'),
      proposedQuantity: readNullableInt(json, 'proposed_quantity') ?? 1,
      inquiryId: readInt(json, 'inquiry_id'),
      listingId: readInt(json, 'listing_id'),
      sellerId: readInt(json, 'seller_id'),
      buyerId: readInt(json, 'buyer_id'),
      proposedAmount: readDecimalString(json, 'proposed_amount'),
      proposedPickupDate: readNullableDateTime(json, 'proposed_pickup_date'),
      paymentMethod: readNullableEnum(
        json,
        'payment_method',
        InquiryPaymentMethod.fromValue,
      ),
      collectionMethod: readNullableEnum(
        json,
        'collection_method',
        InquiryCollectionMethod.fromValue,
      ),
      note: readNullableString(json, 'note'),
      originalPaymentMethod: original == null
          ? null
          : readNullableEnum(
              original,
              'payment_method',
              InquiryPaymentMethod.fromValue,
            ),
      originalCollectionMethod: original == null
          ? null
          : readNullableEnum(
              original,
              'collection_method',
              InquiryCollectionMethod.fromValue,
            ),
      originalPickupDate: original == null
          ? null
          : readNullableDateTime(original, 'pickup_date'),
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

  /// The agreed number of animals. `proposedAmount` is the total price for this
  /// quantity, matching the transaction amount written by the backend.
  final int proposedQuantity;

  /// The pickup date the seller proposed, if any.
  final DateTime? proposedPickupDate;

  /// The seller's proposed terms. Null when the seller kept the buyer's
  /// original preference (the server sends what was actually proposed).
  final InquiryPaymentMethod? paymentMethod;
  final InquiryCollectionMethod? collectionMethod;

  /// An optional note from the seller.
  final String? note;

  /// The buyer's own inquiry preference at the time the offer was made.
  /// Used only to highlight what the seller changed; the values above are the
  /// terms being accepted.
  final InquiryPaymentMethod? originalPaymentMethod;
  final InquiryCollectionMethod? originalCollectionMethod;
  final DateTime? originalPickupDate;

  final OfferStatus status;

  /// Whether the seller changed the buyer's payment preference.
  bool get paymentChanged =>
      paymentMethod != null &&
      originalPaymentMethod != null &&
      paymentMethod != originalPaymentMethod;

  /// Whether the seller changed the buyer's collection preference.
  bool get collectionChanged =>
      collectionMethod != null &&
      originalCollectionMethod != null &&
      collectionMethod != originalCollectionMethod;

  /// Whether the seller proposed a different pickup date.
  bool get pickupDateChanged =>
      proposedPickupDate != null &&
      originalPickupDate != null &&
      !_sameDay(proposedPickupDate!, originalPickupDate!);

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// When the buyer responded, or `null` while the offer is pending.
  final DateTime? respondedAt;

  final DateTime? createdAt;

  /// Whether the seller proposed any term beyond the price.
  bool get hasTerms =>
      proposedPickupDate != null ||
      paymentMethod != null ||
      collectionMethod != null ||
      (note?.isNotEmpty ?? false);

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
