import '../core/utils/json_utils.dart';

/// The category a notification belongs to, used by the mobile filter chips.
///
/// The server decides this value; the client never writes it. `unknown` is a
/// deliberate fallback for a value this client does not yet recognize — a
/// new category added server-side should not break the inbox, it should just
/// render without a chip. Anything not in this enum arrives as `unknown`.
enum NotificationType {
  transactions('transactions'),
  inquiries('inquiries'),
  listings('listings'),
  verification('verification'),
  system('system'),
  sellerVerification('seller_verification'),
  inquiry('inquiry'),
  listing('listing'),
  unknown('unknown');

  const NotificationType(this.value);

  /// The exact lowercase string the API sends.
  final String value;

  /// Parses the API value. Falls back to [unknown] instead of throwing: a
  /// notification's type is not worth crashing the inbox over, and a new
  /// server-side category must not break old clients.
  static NotificationType fromValue(String? value) {
    if (value == null) {
      return NotificationType.unknown;
    }
    for (final NotificationType type in NotificationType.values) {
      if (type.value == value) {
        return type;
      }
    }
    return NotificationType.unknown;
  }

  /// The chip label, or `null` for [unknown] (hidden from filter chips).
  String? get chipLabel {
    switch (this) {
      case NotificationType.transactions:
      case NotificationType.inquiry:
        return 'Transactions';
      case NotificationType.inquiries:
        return 'Inquiries';
      case NotificationType.listings:
      case NotificationType.listing:
        return 'Listings';
      case NotificationType.verification:
      case NotificationType.sellerVerification:
        return 'Verification';
      case NotificationType.system:
        return 'System';
      case NotificationType.unknown:
        return null;
    }
  }
}

/// The server-side action a notification points at, used to deep-link on tap.
enum NotificationAction {
  verification('verification'),
  listing('listing'),
  inquiry('inquiry'),
  transaction('transaction'),
  none('none');

  const NotificationAction(this.value);

  final String value;

  static NotificationAction fromValue(String? value) {
    if (value == null) {
      return NotificationAction.none;
    }
    for (final NotificationAction action in NotificationAction.values) {
      if (action.value == value) {
        return action;
      }
    }
    return NotificationAction.none;
  }
}

/// One notification, as the mobile surface reads it.
///
/// Mirrors `App\Http\Resources\NotificationResource` on the backend field for
/// field. The `data` blob the server stores is already flattened by the
/// resource into `title`, `body`, `type`, `action`, `action_id`, so this
/// model does not need to parse a nested payload.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.action,
    required this.actionId,
    required this.read,
    required this.readAt,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: readString(json, 'id'),
      title: readString(json, 'title'),
      body: readString(json, 'body'),
      type: NotificationType.fromValue(readNullableString(json, 'type')),
      action: NotificationAction.fromValue(readNullableString(json, 'action')),
      actionId: readNullableInt(json, 'action_id'),
      read: json['read'] == true,
      readAt: readNullableDateTime(json, 'read_at'),
      createdAt: readNullableDateTime(json, 'created_at'),
    );
  }

  /// The notification's UUID.
  final String id;

  /// The headline shown in bold at the top of the tile.
  final String title;

  /// The one-line summary below the headline.
  final String body;

  final NotificationType type;

  /// Where a tap should take the user.
  final NotificationAction action;

  /// The id the [action] refers to (listing id, counterpart id, ...).
  final int? actionId;

  final bool read;
  final DateTime? readAt;
  final DateTime? createdAt;

  /// Returns a copy with `read` flipped to true — used by the controller's
  /// optimistic update before the server confirms.
  AppNotification markRead() {
    return AppNotification(
      id: id,
      title: title,
      body: body,
      type: type,
      action: action,
      actionId: actionId,
      read: true,
      readAt: DateTime.now(),
      createdAt: createdAt,
    );
  }

  @override
  String toString() => 'AppNotification($id, $title, read=$read)';
}