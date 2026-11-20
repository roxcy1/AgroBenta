import '../core/utils/json_utils.dart';

/// A kind of notification whose phone push the user can switch off.
///
/// [value] is the exact key `GET`/`PUT /notification-preferences` uses.
enum NotificationCategory {
  transactions(
    'transactions',
    'Transactions',
    'New transactions and status updates',
  ),
  messages('messages', 'Messages', 'New inquiries from buyers'),
  listings('listings', 'Listings', 'Listing approvals and rejections'),
  verification(
    'verification',
    'Seller Verification',
    'Verification approvals and rejections',
  );

  const NotificationCategory(this.value, this.label, this.description);

  final String value;
  final String label;
  final String description;
}

/// The caller's push switches, one per [NotificationCategory].
///
/// Mirrors the `data` of `GET /notification-preferences`: always all four
/// keys, each a boolean. `true` means that category is pushed to the phone.
/// Notifications are stored and listed in the app either way.
class NotificationPreferences {
  const NotificationPreferences({
    required this.transactions,
    required this.messages,
    required this.listings,
    required this.verification,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      transactions: readBool(json, 'transactions'),
      messages: readBool(json, 'messages'),
      listings: readBool(json, 'listings'),
      verification: readBool(json, 'verification'),
    );
  }

  final bool transactions;
  final bool messages;
  final bool listings;
  final bool verification;

  bool isEnabled(NotificationCategory category) {
    switch (category) {
      case NotificationCategory.transactions:
        return transactions;
      case NotificationCategory.messages:
        return messages;
      case NotificationCategory.listings:
        return listings;
      case NotificationCategory.verification:
        return verification;
    }
  }

  /// A copy with [category] set to [enabled].
  NotificationPreferences withCategory(
    NotificationCategory category, {
    required bool enabled,
  }) {
    return NotificationPreferences(
      transactions: category == NotificationCategory.transactions
          ? enabled
          : transactions,
      messages: category == NotificationCategory.messages ? enabled : messages,
      listings: category == NotificationCategory.listings ? enabled : listings,
      verification: category == NotificationCategory.verification
          ? enabled
          : verification,
    );
  }
}
