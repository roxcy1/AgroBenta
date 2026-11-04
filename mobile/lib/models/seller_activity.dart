import '../core/utils/json_utils.dart';
import 'pagination.dart';

/// One genuine seller event from `GET /api/seller/activities`.
///
/// Mirrors `SellerActivityResource`. Only safe, navigation-oriented fields are
/// modelled; the server never sends `metadata`, `admin_note` or `changes`.
/// Context ids are nullable because an event may concern only some targets
/// (for example a listing event has no transaction id).
class SellerActivity {
  const SellerActivity({
    required this.id,
    required this.action,
    required this.label,
    required this.description,
    required this.createdAt,
    required this.targetType,
    required this.targetId,
    required this.listingId,
    required this.buyerId,
    required this.offerId,
    required this.transactionId,
    required this.inquiryId,
  });

  factory SellerActivity.fromJson(Map<String, dynamic> json) {
    // `context` is a JSON object on the wire. Guard against an older/other
    // producer emitting an empty array, which decodes to a List and would
    // otherwise fail the whole feed with a response-shape error.
    final Object? rawContext = json['context'];
    final Map<String, dynamic> context = rawContext is Map
        ? rawContext.cast<String, dynamic>()
        : const <String, dynamic>{};

    return SellerActivity(
      id: readInt(json, 'id'),
      action: readString(json, 'action'),
      label: readString(json, 'label'),
      description: readNullableString(json, 'description'),
      createdAt: readNullableDateTime(json, 'created_at'),
      targetType: readNullableString(json, 'target_type'),
      targetId: readNullableInt(json, 'target_id'),
      listingId: readNullableInt(context, 'listing_id'),
      buyerId: readNullableInt(context, 'buyer_id'),
      offerId: readNullableInt(context, 'offer_id'),
      transactionId: readNullableInt(context, 'transaction_id'),
      inquiryId: readNullableInt(context, 'inquiry_id'),
    );
  }

  final int id;

  /// Machine action, e.g. `offer_accepted`.
  final String action;

  /// Server-provided human label, e.g. "Offer accepted".
  final String label;

  final String? description;
  final DateTime? createdAt;
  final String? targetType;
  final int? targetId;

  /// Navigation context ids. Typed here so the future UI never parses maps.
  final int? listingId;
  final int? buyerId;
  final int? offerId;
  final int? transactionId;
  final int? inquiryId;
}

/// One page of the All Activities feed.
class SellerActivityPage {
  const SellerActivityPage({
    required this.activities,
    required this.pagination,
  });

  final List<SellerActivity> activities;
  final Pagination pagination;
}
