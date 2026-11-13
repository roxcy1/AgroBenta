import '../core/utils/json_utils.dart';
import 'transaction.dart';

/// A completed sale's receipt, from `GET /transactions/{id}/receipt`.
///
/// Mirrors `TransactionReceiptResource` field for field. `total_amount` stays a
/// decimal string; it is formatted only at the display edge and never used for
/// arithmetic. `payment_method` is a recorded preference, not proof that
/// payment happened.
class TransactionReceipt {
  const TransactionReceipt({
    required this.version,
    required this.reference,
    required this.completedAt,
    required this.buyerName,
    required this.sellerName,
    required this.livestockType,
    required this.breed,
    required this.quantity,
    required this.totalAmount,
    required this.paymentMethod,
    required this.collectionMethod,
    required this.status,
  });

  factory TransactionReceipt.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> buyer = readObject(json, 'buyer');
    final Map<String, dynamic> seller = readObject(json, 'seller');
    final Map<String, dynamic> listing = readObject(json, 'listing');

    return TransactionReceipt(
      version: readInt(json, 'version'),
      reference: readString(json, 'reference'),
      completedAt: readNullableDateTime(json, 'completed_at'),
      buyerName: readString(buyer, 'name'),
      sellerName: readString(seller, 'name'),
      livestockType: readString(listing, 'livestock_type'),
      breed: readStringOrEmpty(listing, 'breed'),
      quantity: readInt(json, 'quantity'),
      totalAmount: readDecimalString(json, 'total_amount'),
      paymentMethod: readNullableString(json, 'payment_method'),
      collectionMethod: readNullableString(json, 'collection_method'),
      status: readString(json, 'status'),
    );
  }

  /// Snapshot shape version; 1 is the only shape this app knows.
  final int version;

  /// The stable display reference, e.g. `TRX-001`.
  final String reference;

  /// When the buyer confirmed receipt, or null on an unexpected legacy row.
  final DateTime? completedAt;

  final String buyerName;

  final String sellerName;

  final String livestockType;

  final String breed;

  final int quantity;

  /// The server-derived agreed total, as a decimal string.
  final String totalAmount;

  /// The recorded preference, or null when the transaction recorded none.
  final String? paymentMethod;

  /// The recorded collection preference, or null on a direct/legacy record.
  final String? collectionMethod;

  /// The server's lifecycle value; always `completed` for a valid receipt.
  final String status;

  /// The breed when there is one, otherwise the species.
  String get livestockTitle =>
      breed.trim().isEmpty ? livestockType : breed;

  /// The shared label for the recorded collection preference.
  String get collectionMethodLabel =>
      collectionMethodLabelFor(collectionMethod);

  /// The shared label for the recorded payment preference.
  String get paymentMethodLabel => paymentMethodLabelFor(paymentMethod);
}
