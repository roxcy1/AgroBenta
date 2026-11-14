import '../core/utils/json_utils.dart';
import 'inquiry.dart';

/// The latest offer attached to an inquiry list item, when one exists.
class InquiryOfferSummary {
  const InquiryOfferSummary({
    required this.id,
    required this.status,
    required this.proposedAmount,
    this.proposedQuantity = 1,
  });

  factory InquiryOfferSummary.fromJson(Map<String, dynamic> json) {
    return InquiryOfferSummary(
      id: readInt(json, 'id'),
      status: readString(json, 'status'),
      proposedAmount: readDecimalString(json, 'proposed_amount'),
      proposedQuantity: readNullableInt(json, 'proposed_quantity') ?? 1,
    );
  }

  final int id;

  /// Raw API value: `pending`, `declined`, `withdrawn`, `accepted`, `expired`.
  final String status;

  final String proposedAmount;
  final int proposedQuantity;

  bool get isPending => status == 'pending';
}

/// The listing facts an inquiry list item shows.
class InquiryListItemListing {
  const InquiryListItemListing({
    required this.id,
    required this.title,
    required this.askingPrice,
    required this.photoUrl,
    this.availableQuantity,
    this.inventoryReconciliationRequired = false,
  });

  factory InquiryListItemListing.fromJson(Map<String, dynamic> json) {
    return InquiryListItemListing(
      id: readInt(json, 'id'),
      title: readString(json, 'title'),
      askingPrice: readNullableDecimalString(json, 'asking_price'),
      photoUrl: readNullableString(json, 'photo_url'),
      availableQuantity: readNullableInt(json, 'quantity'),
      inventoryReconciliationRequired:
          readNullableBool(json, 'inventory_reconciliation_required') ?? false,
    );
  }

  final int id;
  final String title;
  final String? askingPrice;
  final String? photoUrl;
  final int? availableQuantity;
  final bool inventoryReconciliationRequired;
}

/// One active inquiry, as `GET /api/inquiries` returns it.
///
/// Mirrors `InquiryListItemResource` field for field. This is not the buyer's
/// create response (`Inquiry`) nor the seller's inbox record
/// (`ReceivedInquiry`): it is side-aware, names the counterpart, and carries the
/// latest offer so the Messages tab can show what still needs negotiating.
class InquiryListItem {
  const InquiryListItem({
    required this.id,
    required this.role,
    required this.listing,
    required this.counterpart,
    required this.paymentMethod,
    required this.collectionMethod,
    required this.preferredSchedule,
    required this.message,
    required this.latestOffer,
    this.requestedQuantity = 1,
    this.canMakeOffer = false,
  });

  factory InquiryListItem.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? listing = readNullableObject(json, 'listing');
    final Map<String, dynamic>? counterpart = readNullableObject(
      json,
      'counterpart',
    );
    final Map<String, dynamic>? offer = readNullableObject(
      json,
      'latest_offer',
    );

    return InquiryListItem(
      id: readInt(json, 'id'),
      requestedQuantity: readNullableInt(json, 'requested_quantity') ?? 1,
      role: readString(json, 'role'),
      listing: listing == null
          ? null
          : InquiryListItemListing.fromJson(listing),
      counterpart: counterpart == null
          ? null
          : InquiryCounterpart(
              id: readInt(counterpart, 'id'),
              name: readString(counterpart, 'name'),
            ),
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
      preferredSchedule: readNullableDateTime(json, 'preferred_schedule'),
      message: readString(json, 'message'),
      latestOffer: offer == null ? null : InquiryOfferSummary.fromJson(offer),
      canMakeOffer: readNullableBool(json, 'can_make_offer') ?? false,
    );
  }

  final int id;

  final int requestedQuantity;

  /// The caller's side: `buyer` or `seller`.
  final String role;

  final InquiryListItemListing? listing;
  final InquiryCounterpart? counterpart;
  final InquiryPaymentMethod? paymentMethod;
  final InquiryCollectionMethod? collectionMethod;
  final DateTime? preferredSchedule;
  final String message;
  final InquiryOfferSummary? latestOffer;

  /// Server-decided eligibility for the seller's Make an Offer action.
  final bool canMakeOffer;

  bool get isBuyer => role == 'buyer';

  /// A buyer with a pending offer must accept or decline it.
  bool get needsBuyerDecision => isBuyer && (latestOffer?.isPending ?? false);

  /// The counterpart's role, used by the chat header.
  String get counterpartRole => isBuyer ? 'Seller' : 'Buyer';
}

/// Identity and name only, matching `UserSummaryResource`.
class InquiryCounterpart {
  const InquiryCounterpart({required this.id, required this.name});

  final int id;
  final String name;
}
