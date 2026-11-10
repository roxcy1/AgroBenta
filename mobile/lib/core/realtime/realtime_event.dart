/// A single server-broadcast event received on the user's private channel.
///
/// Immutable. [data] is the decoded payload — the JSON object the backend's
/// `broadcastWith()` serialized — never a raw JSON string.
class RealtimeEvent {
  const RealtimeEvent({required this.name, required this.data});

  /// The broadcast event name, e.g. `message.sent` or `transaction.updated`.
  final String name;

  /// The decoded payload map (entity ids, status, counterpart ids).
  final Map<String, dynamic> data;

  @override
  String toString() => 'RealtimeEvent(name: $name)';
}
