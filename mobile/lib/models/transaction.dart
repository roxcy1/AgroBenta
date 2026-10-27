import '../core/utils/json_utils.dart';
import 'listing.dart';

/// A transaction's lifecycle state, as stored in `transactions.status`.
///
/// Serialised by `backend/app/Enums/TransactionStatus.php` and surfaced
/// verbatim by `MobileTransactionResource`. [D-15]: `pending` is the only
/// non-terminal state; `completed` and `cancelled` are terminal. Completion
/// itself is unimplemented (OQ-15, backend 501), so `completed` is modelled
/// because terminal records can exist, not because the app can produce them.
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
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
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

  /// Display form of the id: `TRX-001`. The id itself stays an int.
  String get displayId => 'TRX-${id.toString().padLeft(3, '0')}';

  /// Whether the transaction can still change. `pending` is the only
  /// non-terminal state; both exits are terminal and irreversible.
  bool get isPending => status == TransactionStatus.pending;

  @override
  String toString() => 'Transaction($id, ${status.value}, ${role.value})';
}
