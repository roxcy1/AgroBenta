import '../core/utils/json_utils.dart';
import 'listing.dart';

/// A transaction's lifecycle state, as stored in `transactions.status`.
///
/// Serialised by `backend/app/Enums/TransactionStatus.php` and surfaced
/// verbatim by `MobileTransactionResource`. `pending` is the only non-terminal
/// state; `completed` and `cancelled` are terminal. Completion is produced by
/// the buyer confirming receipt after the seller reports pickup or delivery.
enum TransactionStatus {
  pending('pending'),
  completed('completed'),
  cancelled('cancelled');

  const TransactionStatus(this.value);

  /// The exact lowercase string the API sends.
  final String value;

  /// Parses the API value, failing loudly on an unknown one.
  static TransactionStatus fromValue(String value) {
    for (final TransactionStatus status in TransactionStatus.values) {
      if (status.value == value) {
        return status;
      }
    }
    throw FormatException('Unknown transaction status "$value".');
  }
}

/// The separate fulfillment stage recorded by `transactions.fulfillment_status`.
///
/// This is deliberately not part of [TransactionStatus]. The ERD lifecycle
/// remains pending/completed/cancelled, while this progression records what the
/// seller and buyer have reported on the ground. A legacy record may have no
/// stage (`null`), which the UI treats safely.
enum TransactionFulfillmentStatus {
  confirmed('confirmed', 'Confirmed'),
  preparing('preparing', 'Preparing'),
  readyForPickup('ready_for_pickup', 'Ready for Pickup'),
  pickedUp('picked_up', 'Picked Up'),
  onTheWay('on_the_way', 'On the Way'),
  delivered('delivered', 'Delivered'),
  completed('completed', 'Completed');

  const TransactionFulfillmentStatus(this.value, this.label);

  /// The exact lowercase string the API sends.
  final String value;

  /// Display-only label. The API contract is always [value].
  final String label;

  static TransactionFulfillmentStatus? tryFromValue(String? value) {
    if (value == null) {
      return null;
    }
    for (final TransactionFulfillmentStatus status
        in TransactionFulfillmentStatus.values) {
      if (status.value == value) {
        return status;
      }
    }
    return null;
  }
}

/// One server-permitted fulfillment action from `permitted_actions`.
///
/// The server decides which of these the current viewer may perform; the app
/// never infers a button from the stage alone.
enum TransactionFulfillmentAction {
  preparing('preparing', 'Start Preparing', 'Preparation started.'),
  readyForPickup(
    'ready_for_pickup',
    'Mark Ready for Pickup',
    'Marked ready for pickup.',
  ),
  pickedUp('picked_up', 'Confirm Handover', 'Handover confirmed.'),
  onTheWay('on_the_way', 'Mark On the Way', 'Marked on the way.'),
  delivered('delivered', 'Mark Delivered', 'Marked delivered.'),
  confirmReceived(
    'confirm_received',
    'Confirm Received',
    'Receipt confirmed. Transaction completed.',
  );

  const TransactionFulfillmentAction(
    this.value,
    this.label,
    this.successMessage,
  );

  /// The exact lowercase string the API sends in `permitted_actions`.
  final String value;

  /// Display label for the action button.
  final String label;

  /// Confirmation shown after a successful action.
  final String successMessage;

  static TransactionFulfillmentAction? tryFromValue(String? value) {
    if (value == null) {
      return null;
    }
    for (final TransactionFulfillmentAction action
        in TransactionFulfillmentAction.values) {
      if (action.value == value) {
        return action;
      }
    }
    return null;
  }
}

/// Which side of a transaction the viewer is on.
///
/// Server-derived per request. The client never sends or decides this.
enum TransactionRole {
  buyer('buyer'),
  seller('seller');

  const TransactionRole(this.value);

  final String value;

  static TransactionRole fromValue(String value) {
    for (final TransactionRole role in TransactionRole.values) {
      if (role.value == value) {
        return role;
      }
    }
    throw FormatException('Unknown transaction role "$value".');
  }
}

/// The counterparty's contact, as the transaction detail exposes it.
///
/// Only the *other* party is ever present: a buyer sees the seller, a seller
/// sees the buyer. Never both sides at once (F-08).
class TransactionCounterparty {
  const TransactionCounterparty({
    required this.id,
    required this.name,
    required this.email,
  });

  factory TransactionCounterparty.fromJson(Map<String, dynamic> json) {
    return TransactionCounterparty(
      id: readInt(json, 'id'),
      name: readString(json, 'name'),
      email: readString(json, 'email'),
    );
  }

  /// `users.id` of the counterparty.
  final int id;

  final String name;

  final String email;
}

/// The listing snapshot embedded in a transaction.
///
/// Identity, species, breed and photos only. Price and stock are absent: the
/// price that matters is the transaction's own server-derived
/// `total_amount`, and the live `asking_price` beside it would invite a
/// comparison the client must not adjudicate.
class TransactionListing {
  const TransactionListing({
    required this.id,
    required this.livestockType,
    required this.breed,
    required this.photos,
  });

  factory TransactionListing.fromJson(Map<String, dynamic> json) {
    return TransactionListing(
      id: readInt(json, 'id'),
      livestockType: readString(json, 'livestock_type'),
      breed: readStringOrEmpty(json, 'breed'),
      photos: readStringList(json, 'photos'),
    );
  }

  final int id;

  final String livestockType;

  final String breed;

  final List<String> photos;

  /// A buyer-facing title: the breed when there is one, else the species.
  String get title => breed.trim().isEmpty ? livestockType : breed;

  /// The first photo the client can actually fetch, or `null`.
  String? get loadablePhotoUrl {
    for (final String path in photos) {
      if (Listing.isDirectlyLoadablePhotoUrl(path)) {
        return path.trim();
      }
    }
    return null;
  }
}

/// The terms snapshotted when the transaction was created.
///
/// These are recorded preferences, not a payment or logistics service. A null
/// collection method is a legacy/direct record and is rendered as unspecified.
class TransactionTerms {
  const TransactionTerms({
    this.offerId,
    this.pickupDate,
    this.paymentMethod,
    this.collectionMethod,
  });

  factory TransactionTerms.fromJson(Map<String, dynamic> json) {
    return TransactionTerms(
      offerId: readNullableInt(json, 'offer_id'),
      pickupDate: readNullableDateTime(json, 'pickup_date'),
      paymentMethod: readNullableString(json, 'payment_method'),
      collectionMethod: readNullableString(json, 'collection_method'),
    );
  }

  static const TransactionTerms empty = TransactionTerms();

  final int? offerId;
  final DateTime? pickupDate;
  final String? paymentMethod;
  final String? collectionMethod;

  bool get isDelivery => collectionMethod == 'seller_arranged_delivery';

  /// The buyer-facing label for the recorded collection preference.
  String get collectionMethodLabel => switch (collectionMethod) {
    'farm_pickup' => 'Personal Pickup',
    'buyer_arranged_transportation' => 'Buyer-Arranged Transportation',
    'seller_arranged_delivery' => 'Seller-Arranged Delivery',
    'not_sure_yet' => 'Not Sure Yet',
    'discuss_with_seller' => 'Discuss with seller',
    _ => 'Not specified',
  };
}

/// One transaction, as the mobile surface returns it.
///
/// Mirrors `MobileTransactionResource` field for field. `total_amount` stays
/// a `String` — parsed only at the display edge, never used for arithmetic.
/// Any client-side `asking_price x quantity` that differed from this value
/// would be a trust bug, so no such computation exists.
class Transaction {
  const Transaction({
    required this.id,
    required this.role,
    required this.listing,
    required this.counterparty,
    required this.quantity,
    required this.totalAmount,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.terms = TransactionTerms.empty,
    this.fulfillmentStatus,
    this.fulfillmentStatusValue,
    this.permittedActions = const <String>[],
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? terms = readNullableObject(json, 'terms');
    final String? fulfillmentValue = readNullableString(
      json,
      'fulfillment_status',
    );

    return Transaction(
      id: readInt(json, 'id'),
      role: TransactionRole.fromValue(readString(json, 'role')),
      listing: TransactionListing.fromJson(readObject(json, 'listing')),
      counterparty: TransactionCounterparty.fromJson(
        readObject(json, 'counterparty'),
      ),
      quantity: readInt(json, 'quantity'),
      totalAmount: readDecimalString(json, 'total_amount'),
      status: TransactionStatus.fromValue(readString(json, 'status')),
      createdAt: readNullableDateTime(json, 'created_at'),
      updatedAt: readNullableDateTime(json, 'updated_at'),
      terms: terms == null
          ? TransactionTerms.empty
          : TransactionTerms.fromJson(terms),
      fulfillmentStatus: TransactionFulfillmentStatus.tryFromValue(
        fulfillmentValue,
      ),
      fulfillmentStatusValue: fulfillmentValue,
      permittedActions: readStringList(json, 'permitted_actions'),
    );
  }

  /// `transactions.id`.
  final int id;

  /// Which side the viewer is on, decided server-side per request.
  final TransactionRole role;

  final TransactionListing listing;

  /// The other party's contact. Never both parties.
  final TransactionCounterparty counterparty;

  final int quantity;

  /// Server-derived `asking_price x quantity`. Display only.
  final String totalAmount;

  final TransactionStatus status;

  final DateTime? createdAt;

  final DateTime? updatedAt;

  /// The snapshotted collection/payment preferences.
  final TransactionTerms terms;

  /// The recorded fulfillment stage, or null on a legacy record.
  final TransactionFulfillmentStatus? fulfillmentStatus;

  /// The raw server value. It is retained so an unknown non-null stage can be
  /// distinguished from a legacy missing stage instead of being shown as
  /// Confirmed.
  final String? fulfillmentStatusValue;

  /// The actions the server permits for the authenticated viewer.
  final List<String> permittedActions;

  /// Display form of the id: `TRX-001`. The id itself stays an int.
  String get displayId => 'TRX-${id.toString().padLeft(3, '0')}';

  /// Whether the transaction can still change. `pending` is the only
  /// non-terminal state; both exits are terminal and irreversible.
  bool get isPending => status == TransactionStatus.pending;

  /// The stage the UI should show.
  ///
  /// A pending legacy record predates `fulfillment_status`; it starts at
  /// Confirmed. A completed record without a stage is shown as completed.
  /// Cancelled records intentionally return null and use the transaction status
  /// instead.
  TransactionFulfillmentStatus? get effectiveFulfillmentStatus {
    if (fulfillmentStatus != null) {
      return fulfillmentStatus;
    }
    // A non-null raw value that this app does not recognise must not fall back
    // to Confirmed: the screen shows a safe unavailable state instead.
    if (fulfillmentStatusValue != null) {
      return null;
    }
    return switch (status) {
      TransactionStatus.pending => TransactionFulfillmentStatus.confirmed,
      TransactionStatus.completed => TransactionFulfillmentStatus.completed,
      TransactionStatus.cancelled => null,
    };
  }

  /// Whether the server sent a stage this app version does not understand.
  bool get hasUnknownFulfillmentStatus =>
      fulfillmentStatusValue != null && fulfillmentStatus == null;

  /// Whether this is an older pending record with no recorded stage.
  bool get hasLegacyFulfillment =>
      status == TransactionStatus.pending && fulfillmentStatusValue == null;

  bool permits(String action) => permittedActions.contains(action);

  bool get canConfirmReceived =>
      permits(TransactionFulfillmentAction.confirmReceived.value);

  bool get canCancel => permits('cancel');

  /// The one seller step the server permits, if any.
  ///
  /// The order is fixed so a malformed response with several seller actions
  /// can never render more than one primary step.
  TransactionFulfillmentAction? get nextSellerAction {
    for (final TransactionFulfillmentAction action
        in const <TransactionFulfillmentAction>[
          TransactionFulfillmentAction.preparing,
          TransactionFulfillmentAction.readyForPickup,
          TransactionFulfillmentAction.pickedUp,
          TransactionFulfillmentAction.onTheWay,
          TransactionFulfillmentAction.delivered,
        ]) {
      if (permits(action.value)) {
        return action;
      }
    }
    return null;
  }

  @override
  String toString() =>
      'Transaction($id, ${status.value}, ${role.value}, '
      '${fulfillmentStatus?.value ?? 'no-stage'})';
}
