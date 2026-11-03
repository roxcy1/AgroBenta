import '../core/utils/json_utils.dart';
import 'inquiry.dart';

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

/// The structured inquiry payload attached to the message that opened it.
///
/// Mirrors the `inquiry` object `MessageResource` sends. Values are the raw
/// API strings/enums; the widget layer renders their human labels.
class MessageInquiry {
  const MessageInquiry({
    required this.id,
    required this.listing,
    required this.paymentMethod,
    required this.collectionMethod,
    required this.preferredSchedule,
    required this.message,
  });

  factory MessageInquiry.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? listing = readNullableObject(json, 'listing');

    return MessageInquiry(
      id: readInt(json, 'id'),
      listing: listing == null ? null : MessageInquiryListing.fromJson(listing),
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
      message: readString(json, 'message'),
    );
  }

  final int id;
  final MessageInquiryListing? listing;
  final InquiryPaymentMethod? paymentMethod;
  final InquiryCollectionMethod? collectionMethod;
  final DateTime? preferredSchedule;
  final String message;
}

/// The listing facts an inquiry card shows.
class MessageInquiryListing {
  const MessageInquiryListing({
    required this.id,
    required this.title,
    required this.askingPrice,
    required this.photoUrl,
  });

  factory MessageInquiryListing.fromJson(Map<String, dynamic> json) {
    return MessageInquiryListing(
      id: readInt(json, 'id'),
      title: readString(json, 'title'),
      askingPrice: readNullableDecimalString(json, 'asking_price'),
      photoUrl: readNullableString(json, 'photo_url'),
    );
  }

  final int id;
  final String title;
  final String? askingPrice;
  final String? photoUrl;
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
    this.inquiry,
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
      inquiry: json['inquiry'] is Map<String, dynamic>
          ? MessageInquiry.fromJson(json['inquiry'] as Map<String, dynamic>)
          : null,
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

  /// The inquiry this message opened, when the server attached one.
  final MessageInquiry? inquiry;

  /// Whether `userId` sent this message.
  bool isSentBy(int userId) => senderId == userId;

  /// The other party — who this message is *to*, from `userId`'s perspective.
  ChatUser counterpartOf(int userId) => senderId == userId ? receiver : sender;

  @override
  String toString() =>
      'Message($id, from=$senderId, to=$receiverId, read=$read)';
}
