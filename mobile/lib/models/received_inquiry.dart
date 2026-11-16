import '../core/utils/json_utils.dart';
import 'inquiry.dart';

/// The buyer's identity as the seller's inbox exposes it.
///
/// Identity and display name only. `SellerInquiryResource` deliberately omits
/// the buyer's email and every other contact detail (functional documentation
/// section 10.4), so there is no field here to render one.
class InquiryBuyer {
  const InquiryBuyer({required this.id, required this.name});

  factory InquiryBuyer.fromJson(Map<String, dynamic> json) {
    return InquiryBuyer(
      id: readInt(json, 'id'),
      name: readString(json, 'name'),
    );
  }

  final int id;

  final String name;
}

/// One inquiry as the seller receives it.
///
/// Mirrors `backend/app/Http/Resources/SellerInquiryResource.php` field for
/// field. It is separate from [Inquiry] because the two mobile projections
/// differ in a way that matters: the buyer's create response has no buyer and
/// no seller, while the seller's list names the buyer and deliberately carries
/// no administrator-facing `status` and no buyer contact details.
///
/// The inquiry's preference fields reuse the buyer-side enums, because the API
/// values are the same columns. `delivery_fee` stays a decimal [String], like
/// every other money field in this app, and is formatted only at the display
/// edge.
class ReceivedInquiry {
  const ReceivedInquiry({
    required this.id,
    required this.buyer,
    required this.listing,
    required this.subject,
    required this.message,
    required this.purchaseInterest,
    required this.transactionMethod,
    required this.deliveryMethod,
    required this.deliveryFee,
    required this.contactMethod,
    required this.preferredSchedule,
    required this.collectionDateOption,
    required this.paymentMethod,
    required this.collectionMethod,
    required this.createdAt,
    this.requestedQuantity = 1,
    this.canMakeOffer = true,
  });

  factory ReceivedInquiry.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? buyer = readNullableObject(json, 'buyer');
    final Map<String, dynamic>? listing = readNullableObject(json, 'listing');

    return ReceivedInquiry(
      id: readInt(json, 'id'),
      requestedQuantity: readNullableInt(json, 'requested_quantity') ?? 1,
      buyer: buyer == null ? null : InquiryBuyer.fromJson(buyer),
      listing: listing == null ? null : InquiryListing.fromJson(listing),
      subject: readNullableString(json, 'subject'),
      message: readString(json, 'message'),
      purchaseInterest: readNullableBool(json, 'purchase_interest'),
      transactionMethod: readNullableEnum(
        json,
        'transaction_method',
        InquiryTransactionMethod.fromValue,
      ),
      deliveryMethod: readNullableEnum(
        json,
        'delivery_method',
        InquiryDeliveryMethod.fromValue,
      ),
      deliveryFee: readNullableDecimalString(json, 'delivery_fee'),
      contactMethod: readNullableEnum(
        json,
        'contact_method',
        InquiryContactMethod.fromValue,
      ),
      preferredSchedule: readNullableDateTime(json, 'preferred_schedule'),
      collectionDateOption: readNullableEnum(
        json,
        'collection_date_option',
        InquiryCollectionDateOption.fromValue,
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
      createdAt: readNullableDateTime(json, 'created_at'),
      canMakeOffer: readNullableBool(json, 'can_make_offer') ?? true,
    );
  }

  /// `inquiries.id`.
  final int id;

  final int requestedQuantity;

  /// The buyer who sent the inquiry. Null only if the server response is
  /// missing a projection it always sends, which the screen handles as
  /// "Unknown buyer" rather than crashing the list.
  final InquiryBuyer? buyer;

  /// The listing asked about, or `null` if it was deleted afterwards. The
  /// inquiry remains valid without it.
  final InquiryListing? listing;

  /// The subject line, when one was chosen.
  final String? subject;

  /// The buyer's message, required and at most 500 characters.
  final String message;

  /// Whether the buyer said they want to buy.
  final bool? purchaseInterest;

  /// The buyer's preferred deal structure, or `null` for none stated.
  final InquiryTransactionMethod? transactionMethod;

  /// How the buyer proposes to take delivery, or `null` for none stated.
  final InquiryDeliveryMethod? deliveryMethod;

  /// The buyer's proposed delivery fee as the API sent it, e.g. `"1500.00"`.
  final String? deliveryFee;

  /// How the buyer asked to be reached.
  final InquiryContactMethod? contactMethod;

  /// The date the buyer hopes to transact, as a preference, not an appointment.
  final DateTime? preferredSchedule;

  /// The buyer's collection-date preference. `specificDate` pairs with
  /// [preferredSchedule]; the two relative options carry no date.
  final InquiryCollectionDateOption? collectionDateOption;

  /// The buyer's preferred way to pay. A preference only — no payment is
  /// created or processed.
  final InquiryPaymentMethod? paymentMethod;

  /// How the buyer proposes to receive the livestock. A preference only.
  final InquiryCollectionMethod? collectionMethod;

  final DateTime? createdAt;

  /// Server-decided: a new offer is allowed only while the inquiry is open,
  /// nothing is pending and nothing has been accepted.
  final bool canMakeOffer;

  @override
  String toString() => 'ReceivedInquiry($id, ${buyer?.id ?? 'no buyer'})';
}
