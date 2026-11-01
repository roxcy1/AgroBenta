import '../core/utils/json_utils.dart';
import 'message.dart';

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
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      counterpart: ChatUser.fromJson(readObject(json, 'counterpart')),
      listingId: readNullableInt(json, 'listing_id'),
      listingTitle: readNullableString(json, 'listing_title'),
      lastMessage: readString(json, 'last_message'),
      lastMessageAt: readNullableDateTime(json, 'last_message_at'),
      unreadCount: readInt(json, 'unread_count'),
      hasInquiry: readBool(json, 'has_inquiry'),
      hasTransaction: readBool(json, 'has_transaction'),
    );
  }

  final ChatUser counterpart;

  /// The listing context of the newest message, if any. Not the conversation's
  /// identity — a pair's thread survives the listing.
  final int? listingId;

  final String? listingTitle;
  final String lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;

  /// Whether an inquiry exists between the caller and [counterpart].
  final bool hasInquiry;

  /// Whether a transaction exists between the caller and [counterpart].
  final bool hasTransaction;

  /// Whether this conversation has unread messages.
  bool get hasUnread => unreadCount > 0;

  @override
  String toString() => 'Conversation(${counterpart.name}, unread=$unreadCount)';
}
