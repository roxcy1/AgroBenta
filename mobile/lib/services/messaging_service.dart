import '../core/constants/api_constants.dart';
import '../core/network/api_client.dart';
import '../models/conversation.dart';
import '../models/message.dart';

/// The messaging transport.
///
/// Thin on purpose: every request goes through [ApiClient], which owns the
/// bearer token, the envelope unwrapping and the `401` handling. The service's
/// only jobs are to know the paths and to shape responses into models.
///
/// ## Why the shapes are read from `data` and not from `data.items`
///
/// The backend's message endpoints use the same `{ success, message, data }`
/// envelope as every other feature. `ApiClient` unwraps it before handing the
/// payload to `parse`, so the service sees the `data` object directly. The
/// conversations endpoint wraps its list under a `conversations` key; the
/// thread endpoint wraps its list under `messages` with a `pagination` sibling.
/// That asymmetry is the backend's, and it is mirrored here rather than
/// flattened, so a change to either shape is one edit in one place.
class MessagingService {
  const MessagingService(this._client);

  final ApiClient _client;

  /// `GET /conversations` — the caller's inbox.
  Future<List<Conversation>> conversations() {
    return _client.get<List<Conversation>>(
      MessagingEndpoints.conversations,
      parse: (Object? data) {
        final Map<String, dynamic> map = _asMap(data);
        final List<dynamic> raw =
            (map['conversations'] as List<dynamic>?) ?? const <dynamic>[];
        return raw
            .whereType<Map<String, dynamic>>()
            .map(Conversation.fromJson)
            .toList(growable: false);
      },
    );
  }

  /// `GET /conversations/{counterpartId}/messages` — one thread.
  ///
  /// Returns just the message list. Pagination is discarded: the chat screen
  /// loads the newest page and grows upward with `loadMore`, but the thread
  /// is bounded by what the two users have said to each other and a chat with
  /// more than a page of history is the exception rather than the rule.
  Future<List<Message>> thread({
    required int counterpartId,
    int? listingId,
    int page = 1,
    int? perPage,
  }) {
    return _client.get<List<Message>>(
      MessagingEndpoints.thread(counterpartId),
           query: <String, dynamic>{
        'listing_id': ?listingId,
        'page': page,
        'per_page': ?perPage,
      },
      parse: (Object? data) {
        final Map<String, dynamic> map = _asMap(data);
        final List<dynamic> raw =
            (map['messages'] as List<dynamic>?) ?? const <dynamic>[];
        return raw
            .whereType<Map<String, dynamic>>()
            .map(Message.fromJson)
            .toList(growable: false);
      },
    );
  }

  /// `POST /messages` — send.
  Future<Message> send({
    required int receiverId,
    required String body,
    int? listingId,
  }) {
    return _client.post<Message>(
      MessagingEndpoints.send,
            body: <String, dynamic>{
        'receiver_id': receiverId,
        'listing_id': ?listingId,
        'body': body,
      },
      parse: (Object? data) => Message.fromJson(_asMap(data)),
    );
  }

  /// `POST /conversations/{counterpartId}/read` — mark the thread read.
  ///
  /// Returns the number of messages flipped from unread to read.
  Future<int> markThreadRead({
    required int counterpartId,
    int? listingId,
  }) {
    return _client.post<int>(
      MessagingEndpoints.markRead(counterpartId),
            body: <String, dynamic>{
        'listing_id': ?listingId,
      },
      parse: (Object? data) {
        final Map<String, dynamic> map = _asMap(data);
        return map['updated'] is int ? map['updated'] as int : 0;
      },
    );
  }

  /// `PATCH /messages/{id}/read` — mark one message read.
  Future<Message> markOneRead(int messageId) {
    return _client.patch<Message>(
      MessagingEndpoints.markOneRead(messageId),
      parse: (Object? data) => Message.fromJson(_asMap(data)),
    );
  }

  static Map<String, dynamic> _asMap(Object? data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return data.cast<String, dynamic>();
    }
    throw const FormatException('Expected a JSON object.');
  }
}