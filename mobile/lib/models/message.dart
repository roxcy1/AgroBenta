import '../core/utils/json_utils.dart';

/// A minimal user summary, as embedded in a message or conversation.
///
/// Only the fields a chat UI needs — id, name, avatar. Not the full
/// `User` model: a message is not the place to leak phone numbers or emails
/// between users who have not agreed to share them.
class ChatUser {
  const ChatUser({
    required this.id,
    required this.name,
    required this.avatarUrl,
  });

  factory ChatUser.fromJson(Map<String, dynamic> json) {
    return ChatUser(
      id: readInt(json, 'id'),
      name: readString(json, 'name'),
      avatarUrl: readNullableString(json, 'avatar_url'),
    );
  }

  final int id;
  final String name;
  final String? avatarUrl;

  /// The initial letter for the fallback avatar.
  String get initial => name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
}

/// One message in a thread.
///
/// Mirrors `MessageResource` on the backend. `sender` and `receiver` are
/// eagerly loaded so a bubble can render the counterpart's name without a
/// second request.
class Message {
  const Message({
    required this.id,
    required this.body,
    required this.senderId,
    required this.receiverId,
    required this.listingId,
    required this.read,
    required this.readAt,
    required this.createdAt,
    required this.sender,
    required this.receiver,
  });

    factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: readInt(json, 'id'),
      body: readString(json, 'body'),
      senderId: readInt(json, 'sender_id'),
      receiverId: readInt(json, 'receiver_id'),
      listingId: readNullableInt(json, 'listing_id'),
      read: json['read'] == true,
      readAt: readNullableDateTime(json, 'read_at'),
      createdAt: readNullableDateTime(json, 'created_at'),
      sender: ChatUser.fromJson(readObject(json, 'sender')),
      receiver: ChatUser.fromJson(readObject(json, 'receiver')),
    );
  }

  final int id;
  final String body;
  final int senderId;
  final int receiverId;
  final int? listingId;
  final bool read;
  final DateTime? readAt;
  final DateTime? createdAt;
  final ChatUser sender;
  final ChatUser receiver;

  /// Whether `userId` sent this message.
  bool isSentBy(int userId) => senderId == userId;

  /// The other party — who this message is *to*, from `userId`'s perspective.
  ChatUser counterpartOf(int userId) =>
      senderId == userId ? receiver : sender;

  @override
  String toString() => 'Message($id, from=$senderId, to=$receiverId, read=$read)';
}