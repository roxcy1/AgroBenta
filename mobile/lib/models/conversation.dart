import '../core/utils/json_utils.dart';
import 'message.dart';

/// One conversation in the caller's inbox, derived from the messages they
/// have exchanged.
///
/// Mirrors `ConversationResource` on the backend. There is no
/// `conversations` table — a conversation is the pair
/// `(counterpart_id, listing_id)` over the caller's messages. This model
/// is what the client renders, not what the server stores.
class Conversation {
  const Conversation({
    required this.counterpart,
    required this.listingId,
    required this.listingTitle,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.unreadCount,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      counterpart: ChatUser.fromJson(readObject(json, 'counterpart')),
      listingId: readNullableInt(json, 'listing_id'),
      listingTitle: readNullableString(json, 'listing_title'),
      lastMessage: readString(json, 'last_message'),
      lastMessageAt: readNullableDateTime(json, 'last_message_at'),
      unreadCount: readInt(json, 'unread_count'),
    );
  }

  final ChatUser counterpart;
  final int? listingId;
  final String? listingTitle;
  final String lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;

  /// Whether this conversation has unread messages.
  bool get hasUnread => unreadCount > 0;

  @override
  String toString() =>
      'Conversation(${counterpart.name}, unread=$unreadCount)';
}