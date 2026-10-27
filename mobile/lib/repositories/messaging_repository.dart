import '../core/constants/api_constants.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../services/messaging_service.dart';

/// Orchestration for messaging.
///
/// Thin, like every other repository in this app: the transport sits behind
/// [MessagingService], so the only policy worth owning here is the page size.
/// The server caps `per_page` at 50 with a `422`, and that limit is a fact
/// about the API rather than about any screen. Clamping it here means no
/// widget can discover the cap by provoking an error — the same rule
/// [TransactionRepository] follows.
///
/// Error translation is deliberately **not** done here. `ApiException.message`
/// is already curated to be displayable, so a second translation layer would
/// be a second place for wording to drift.
class MessagingRepository {
  const MessagingRepository(this._service);

  final MessagingService _service;

  /// The caller's inbox.
  Future<List<Conversation>> conversations() => _service.conversations();

  /// One thread, ordered newest first.
  Future<List<Message>> thread({
    required int counterpartId,
    int? listingId,
    int page = 1,
    int? perPage,
  }) {
    return _service.thread(
      counterpartId: counterpartId,
      listingId: listingId,
      page: page < 1 ? 1 : page,
      perPage: _clampPerPage(perPage),
    );
  }

  /// Sends a message to `receiverId`, optionally tied to a listing.
  Future<Message> send({
    required int receiverId,
    required String body,
    int? listingId,
  }) {
    return _service.send(
      receiverId: receiverId,
      body: body,
      listingId: listingId,
    );
  }

  /// Marks every unread message from `counterpartId` as read.
  ///
  /// Returns the number of messages that changed state — zero on a thread
  /// that is already fully read, which is not an error.
  Future<int> markThreadRead({
    required int counterpartId,
    int? listingId,
  }) {
    return _service.markThreadRead(
      counterpartId: counterpartId,
      listingId: listingId,
    );
  }

  /// Marks one message as read.
  Future<Message> markOneRead(int messageId) => _service.markOneRead(messageId);

  static int _clampPerPage(int? perPage) {
    final int requested = perPage ?? MessagingEndpoints.defaultPerPage;
    if (requested < 1) {
      return 1;
    }
    if (requested > MessagingEndpoints.maxPerPage) {
      return MessagingEndpoints.maxPerPage;
    }
    return requested;
  }
}