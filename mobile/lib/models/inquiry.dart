import '../core/utils/json_utils.dart';

/// The buyer's preferred transaction method, as stored in
/// `inquiries.transaction_method`.
///
/// Serialised by `backend/app/Enums/InquiryTransactionMethod.php` and surfaced
/// verbatim by `MobileInquiryResource`. A preference the buyer expresses, never
/// an agreement: selecting one creates no transaction, payment or delivery
/// booking (design spec §3.4).
enum InquiryTransactionMethod {
  directDeal('direct_deal'),
  arrangeDelivery('arrange_delivery');

  const InquiryTransactionMethod(this.value);

  /// The exact lowercase string the API sends.
  final String value;

  /// The buyer-facing label for the confirmation summary. Display-only; the
  /// API contract is always [value].
  String get label => switch (this) {
    InquiryTransactionMethod.directDeal => 'Direct Deal',
    InquiryTransactionMethod.arrangeDelivery => 'Arrange Delivery',
  };

  /// Parses the API value, failing loudly on an unknown one.
  static InquiryTransactionMethod fromValue(String value) {
    for (final InquiryTransactionMethod method
        in InquiryTransactionMethod.values) {
      if (method.value == value) {
        return method;
      }
    }
    throw FormatException('Unknown transaction method "$value".');
  }
}

/// How the buyer proposes to take delivery, as stored in
/// `inquiries.delivery_method`.
///
/// The column is a plain `string`, not an enum — the two values are the
/// mobile client's own vocabulary, defined here because the form is the only
/// thing that writes them and a second writer would need its own decision.
/// `buyer_pickup` means the buyer collects the livestock themselves;
/// `arrange_delivery` means the buyer arranges transport. Nothing here implies
/// AgroBenta provides, books or tracks transportation (design spec §3.5).
enum InquiryDeliveryMethod {
  buyerPickup('buyer_pickup'),
  arrangeDelivery('arrange_delivery');

  const InquiryDeliveryMethod(this.value);

  final String value;

  /// The buyer-facing label for the confirmation summary. Display-only; the
  /// API contract is always [value].
  String get label => switch (this) {
    InquiryDeliveryMethod.buyerPickup => 'Buyer Pickup',
    InquiryDeliveryMethod.arrangeDelivery => 'Arrange Delivery',
  };

  static InquiryDeliveryMethod fromValue(String value) {
    for (final InquiryDeliveryMethod method in InquiryDeliveryMethod.values) {
      if (method.value == value) {
        return method;
      }
    }
    throw FormatException('Unknown delivery method "$value".');
  }
}

/// How the seller should reach the buyer, as stored in
/// `inquiries.contact_method`.
///
/// One supported value: `in_app_message`, which is exactly the messaging
/// feature that exists. The single case is modelled as an enum rather than a
/// string so a second contact method cannot be shown or sent without a
/// decision about what it means — and in particular so no code path ever
/// populates this with a private seller phone number or address
/// (functional documentation §10.4).
enum InquiryContactMethod {
  inAppMessage('in_app_message');

  const InquiryContactMethod(this.value);

  final String value;

  /// The buyer-facing label for the confirmation summary. Display-only; the
  /// API contract is always [value].
  String get label => 'In-app Message';

  static InquiryContactMethod fromValue(String value) {
    for (final InquiryContactMethod method in InquiryContactMethod.values) {
      if (method.value == value) {
        return method;
      }
    }
    throw FormatException('Unknown contact method "$value".');
  }
}

/// The buyer's preferred way to pay the seller, as stored in
/// `inquiries.payment_method`.
///
/// Serialised by `backend/app/Enums/InquiryPaymentMethod.php` and surfaced
/// verbatim by `MobileInquiryResource`. A preference only — selecting one does
/// not create a payment, and AgroBenta does not process payments
/// (design spec §3.6). `other` is "Other / Discuss with seller".
enum InquiryPaymentMethod {
  cash('cash'),
  gcash('gcash'),
  maya('maya'),
  other('other');

  const InquiryPaymentMethod(this.value);

  final String value;

  /// The buyer-facing label for the confirmation summary. Display-only; the
  /// API contract is always [value].
  String get label => switch (this) {
    InquiryPaymentMethod.cash => 'Cash',
    InquiryPaymentMethod.gcash => 'GCash',
    InquiryPaymentMethod.maya => 'Maya',
    InquiryPaymentMethod.other => 'Other / Discuss with seller',
  };

  static InquiryPaymentMethod fromValue(String value) {
    for (final InquiryPaymentMethod method in InquiryPaymentMethod.values) {
      if (method.value == value) {
        return method;
      }
    }
    throw FormatException('Unknown payment method "$value".');
  }
}

/// The buyer's preferred way to receive the livestock, as stored in
/// `inquiries.collection_method`.
///
/// Serialised by `backend/app/Enums/InquiryCollectionMethod.php` and surfaced
/// verbatim by `MobileInquiryResource`. A preference only — selecting one does
/// not book transportation, and AgroBenta does not provide, book, or track
/// riders (design spec §3.6). `discussWithSeller` is "Discuss arrangements
/// with the seller".
enum InquiryCollectionMethod {
  farmPickup('farm_pickup'),
  buyerArrangedTransportation('buyer_arranged_transportation'),
  discussWithSeller('discuss_with_seller');

  const InquiryCollectionMethod(this.value);

  final String value;

  /// The buyer-facing label for the confirmation summary. Display-only; the
  /// API contract is always [value].
  String get label => switch (this) {
    InquiryCollectionMethod.farmPickup => 'Pick up from the seller\'s farm',
    InquiryCollectionMethod.buyerArrangedTransportation =>
      'Arrange my own livestock transportation',
    InquiryCollectionMethod.discussWithSeller =>
      'Discuss arrangements with the seller',
  };

  static InquiryCollectionMethod fromValue(String value) {
    for (final InquiryCollectionMethod method
        in InquiryCollectionMethod.values) {
      if (method.value == value) {
        return method;
      }
    }
    throw FormatException('Unknown collection method "$value".');
  }
}

/// The buyer's chosen collection-date preference for an inquiry.
///
/// `specificDate` means the buyer named a concrete date (sent in
/// `preferred_schedule`, which must not be in the past). `nextFewDays` and
/// `thisWeek` are relative preferences and do not require a date.
enum InquiryCollectionDateOption {
  specificDate('specific_date'),
  nextFewDays('next_few_days'),
  thisWeek('this_week');

  const InquiryCollectionDateOption(this.value);

  /// The exact lowercase string the API sends.
  final String value;

  static InquiryCollectionDateOption fromValue(String value) {
    for (final InquiryCollectionDateOption option in values) {
      if (option.value == value) {
        return option;
      }
    }
    throw FormatException('Unknown collection date option "$value".');
  }
}

/// The listing snapshot embedded in an inquiry response.
///
/// Identity and the two species fields only — the same narrow shape the
/// transaction resource echoes, so the confirmation can name what was asked
/// about without a second request.
class InquiryListing {
  const InquiryListing({
    required this.id,
    required this.livestockType,
    required this.breed,
  });

  factory InquiryListing.fromJson(Map<String, dynamic> json) {
    return InquiryListing(
      id: readInt(json, 'id'),
      livestockType: readString(json, 'livestock_type'),
      breed: readStringOrEmpty(json, 'breed'),
    );
  }

  final int id;

  final String livestockType;

  final String breed;

  /// A buyer-facing title: the breed when there is one, else the species.
  String get title => breed.trim().isEmpty ? livestockType : breed;
}

/// One inquiry, as the mobile surface returns it.
///
/// Mirrors `backend/app/Http/Resources/MobileInquiryResource.php` field for
/// field. There is deliberately **no `status`**: the workflow marker is an
/// administrator bookmark that gates no mobile behaviour, so modelling it here
/// would invite the client to render a state it has no business acting on, and
/// there is no seller or email projection because the buyer is the reader.
///
/// `delivery_fee` stays a decimal [String], like every other money field in
/// this app — formatted only at the display edge (mobile/AGENTS.md §B).
class Inquiry {
  const Inquiry({
    required this.id,
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
    this.conversationCounterpartId,
  });

  factory Inquiry.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? listing = readNullableObject(json, 'listing');

    return Inquiry(
      id: readInt(json, 'id'),
      listing: listing == null ? null : InquiryListing.fromJson(listing),
      subject: readNullableString(json, 'subject'),
      message: readStringOrEmpty(json, 'message'),
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
      conversationCounterpartId: readNullableInt(json, 'conversation_counterpart_id'),
    );
  }

  /// `inquiries.id`.
  final int id;

  /// The listing asked about, or `null` if the listing was deleted after the
  /// inquiry was sent. The inquiry itself remains valid without it.
  final InquiryListing? listing;

  /// The subject line, when one was chosen.
  final String? subject;

  /// The buyer's message, required and at most 500 characters.
  final String message;

  /// Whether the buyer said they want to buy. `null` only if the server
  /// response omits it — the form always sends one.
  final bool? purchaseInterest;

  /// The buyer's preferred deal structure, or `null` for none stated.
  final InquiryTransactionMethod? transactionMethod;

  /// How the buyer proposes to take delivery, or `null` for none stated.
  final InquiryDeliveryMethod? deliveryMethod;

  /// The proposed delivery fee as the API sent it, e.g. `"1500.00"`.
  ///
  /// Kept as a `String` end to end. It is the buyer's proposed figure, not a
  /// calculated or confirmed charge, and it is never added to the asking price
  /// (design spec §3.5).
  final String? deliveryFee;

  /// How the seller should reach the buyer.
  final InquiryContactMethod? contactMethod;

  /// The date the buyer hopes to transact, as a preference — not an
  /// appointment. `null` when none was chosen.
  final DateTime? preferredSchedule;

  /// How the buyer prefers to pay the seller, or `null` for none stated.
  final InquiryPaymentMethod? paymentMethod;

  /// How the buyer plans to receive the livestock, or `null` for none stated.
  final InquiryCollectionMethod? collectionMethod;

  /// The buyer's chosen collection-date preference.
  final InquiryCollectionDateOption? collectionDateOption;

  /// The conversation counterpart (seller) id, so the buyer can open the exact
  /// thread from "Go to Messages".
  final int? conversationCounterpartId;

  final DateTime? createdAt;

  @override
  String toString() => 'Inquiry($id, ${listing?.id ?? 'listing deleted'})';
}
