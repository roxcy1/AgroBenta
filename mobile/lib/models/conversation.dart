import '../core/utils/json_utils.dart';
import 'inquiry.dart';
import 'message.dart';
import 'offer.dart';

/// The offer summary the inbox preview renders for one conversation.
///
/// This is deliberately **not** [Offer]: the inbox needs the state and the
/// amount, not the parties or the response timestamps. It mirrors the
/// `latest_offer` object `ConversationResource` sends.
class ConversationOffer {
  const ConversationOffer({
    required this.id,
    required this.status,
    required this.proposedAmount,
    required this.listingId,
    required this.listingTitle,
  });

  /// Parses the payload, or returns `null` when the status is not one this app
  /// knows. An unknown offer state must not break the whole inbox.
  static ConversationOffer? tryFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }

    final String status = readString(json, 'status');
    OfferStatus? parsed;
    for (final OfferStatus candidate in OfferStatus.values) {
      if (candidate.value == status) {
        parsed = candidate;
        break;
      }
    }

    if (parsed == null) {
      return null;
    }

    return ConversationOffer(
      id: readInt(json, 'id'),
      status: parsed,
      proposedAmount: readString(json, 'proposed_amount'),
      listingId: readNullableInt(json, 'listing_id'),
      listingTitle: readNullableString(json, 'listing_title'),
    );
  }

  final int id;
  final OfferStatus status;

  /// The proposed final price, as the API sent it, e.g. `"47500.00"`.
  final String proposedAmount;

  final int? listingId;
  final String? listingTitle;

  bool get isPending => status.isPending;
}

/// The inquiry a seller can still turn into an offer from the chat.
///
/// Mirrors the `eligible_inquiry` object on `ConversationResource`. The server
/// already excluded inquiries that have a pending offer and inquiries where the
/// caller is the buyer, so the client never guesses eligibility.
class ConversationEligibleInquiry {
  const ConversationEligibleInquiry({
    required this.id,
    required this.listingId,
    required this.listingTitle,
    this.askingPrice,
    this.photoUrl,
    this.paymentMethod,
    this.collectionMethod,
    this.preferredSchedule,
  });

  factory ConversationEligibleInquiry.fromJson(Map<String, dynamic> json) {
    return ConversationEligibleInquiry(
      id: readInt(json, 'id'),
      listingId: readNullableInt(json, 'listing_id'),
      listingTitle: readNullableString(json, 'listing_title'),
      askingPrice: readNullableDecimalString(json, 'asking_price'),
      photoUrl: readNullableString(json, 'listing_photo_url'),
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
    );
  }

  final int id;
  final int? listingId;
  final String? listingTitle;

  /// The listing's asking price when the offer form opens, as the API sent it.
  final String? askingPrice;

  /// The listing's first photo, already an absolute URL.
  final String? photoUrl;

  /// The buyer's original preference, used to prefill the offer form.
  final InquiryPaymentMethod? paymentMethod;
  final InquiryCollectionMethod? collectionMethod;
  final DateTime? preferredSchedule;
}

/// One conversation in the caller's inbox, derived from the messages they
/// have exchanged.
///
/// Mirrors `ConversationResource` on the backend. There is no
/// `conversations` table — a conversation is the pair of users over the
/// caller's messages. `listing_id` is only the listing context of the newest
/// message, not part of the conversation's identity: a buyer and a seller keep
/// one thread even when they discuss several listings.
///
/// `has_inquiry` and `has_transaction` are pair-level facts computed by the
/// server: they say whether any inquiry or transaction exists between these
/// two users. They are what the inbox filters read, so a filter never guesses
/// from a listing id and never invents a category.
///
/// `roles` says which side(s) the caller acts on: `buyer`, `seller`, both, or
/// neither. An empty list is an unclassifiable legacy thread and is shown in
/// both account modes rather than hidden.
class Conversation {
  const Conversation({
    required this.counterpart,
    required this.listingId,
    required this.listingTitle,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.unreadCount,
    required this.hasInquiry,
    required this.hasTransaction,
    this.listingPrice,
    this.roles = const <String>[],
    this.listingCount = 0,
    this.latestOffer,
    this.eligibleInquiry,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? offer = readNullableObject(
      json,
      'latest_offer',
    );
    final Map<String, dynamic>? inquiry = readNullableObject(
      json,
      'eligible_inquiry',
    );

    return Conversation(
      counterpart: ChatUser.fromJson(readObject(json, 'counterpart')),
      listingId: readNullableInt(json, 'listing_id'),
      listingTitle: readNullableString(json, 'listing_title'),
      listingPrice: readNullableString(json, 'listing_price'),
      lastMessage: readString(json, 'last_message'),
      lastMessageAt: readNullableDateTime(json, 'last_message_at'),
      unreadCount: readInt(json, 'unread_count'),
      hasInquiry: readBool(json, 'has_inquiry'),
      hasTransaction: readBool(json, 'has_transaction'),
      roles: readStringList(json, 'roles'),
      listingCount: readNullableInt(json, 'listing_count') ?? 0,
      latestOffer: ConversationOffer.tryFromJson(offer),
      eligibleInquiry: inquiry == null
          ? null
          : ConversationEligibleInquiry.fromJson(inquiry),
    );
  }

  final ChatUser counterpart;

  /// The listing context of the newest message, if any. Not the conversation's
  /// identity — a pair's thread survives the listing.
  final int? listingId;

  final String? listingTitle;

  /// The asking price of the listing the preview names, as the API sent it.
  final String? listingPrice;
  final String lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;

  /// Whether an inquiry exists between the caller and [counterpart].
  final bool hasInquiry;

  /// Whether a transaction exists between the caller and [counterpart].
  final bool hasTransaction;

  /// The caller's side(s) in this thread: a subset of `buyer`/`seller`.
  final List<String> roles;

  /// How many distinct listings this thread discusses.
  final int listingCount;

  /// The newest offer between the pair, when there is one.
  final ConversationOffer? latestOffer;

  /// The inquiry a seller may still answer with an offer.
  final ConversationEligibleInquiry? eligibleInquiry;

  /// Whether this conversation has unread messages.
  bool get hasUnread => unreadCount > 0;

  /// Whether the thread has no determinable side.
  bool get isUnclassified => roles.isEmpty;

  /// The counterpart's role in this thread, when it is unambiguous.
  ///
  /// Only a thread where the caller acts on exactly one side has a single
  /// answer; a pair that trades both ways (or an unclassified thread) returns
  /// null so the header does not guess.
  String? get counterpartRole {
    if (roles.length != 1) {
      return null;
    }
    return roles.single == 'seller' ? 'Buyer' : 'Seller';
  }

  /// Whether the thread belongs in the given account mode.
  ///
  /// A thread where the caller acts in both roles appears in both modes — it is
  /// the same buyer–seller pair — and an unclassified thread is never hidden.
  bool matchesMode({required bool sellerMode}) {
    if (roles.isEmpty) {
      return true;
    }
    return roles.contains(sellerMode ? 'seller' : 'buyer');
  }

  /// Returns a copy with a different unread count, for the optimistic
  /// mark-as-read in the inbox.
  Conversation copyWith({int? unreadCount}) {
    return Conversation(
      counterpart: counterpart,
      listingId: listingId,
      listingTitle: listingTitle,
      listingPrice: listingPrice,
      lastMessage: lastMessage,
      lastMessageAt: lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      hasInquiry: hasInquiry,
      hasTransaction: hasTransaction,
      roles: roles,
      listingCount: listingCount,
      latestOffer: latestOffer,
      eligibleInquiry: eligibleInquiry,
    );
  }

  @override
  String toString() => 'Conversation(${counterpart.name}, unread=$unreadCount)';
}
