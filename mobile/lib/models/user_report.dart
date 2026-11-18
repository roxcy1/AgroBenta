import '../core/utils/json_utils.dart';

/// The approved report reasons. The values are the exact wire strings.
enum UserReportReason {
  scamFraud('scam_fraud', 'Scam/Fraud'),
  harassment('harassment', 'Harassment'),
  misleadingInformation('misleading_information', 'Misleading Information'),
  spamSuspiciousActivity(
    'spam_suspicious_activity',
    'Spam/Suspicious Activity',
  ),
  inappropriateContent('inappropriate_content', 'Inappropriate Content'),
  other('other', 'Other');

  const UserReportReason(this.value, this.label);

  final String value;
  final String label;

  static UserReportReason fromValue(String value) {
    for (final UserReportReason reason in UserReportReason.values) {
      if (reason.value == value) {
        return reason;
      }
    }
    throw FormatException('Unknown user report reason "$value".');
  }
}

enum UserReportStatus {
  pending('pending'),
  dismissed('dismissed'),
  actioned('actioned');

  const UserReportStatus(this.value);

  final String value;

  static UserReportStatus fromValue(String value) {
    for (final UserReportStatus status in UserReportStatus.values) {
      if (status.value == value) {
        return status;
      }
    }
    throw FormatException('Unknown user report status "$value".');
  }
}

/// The reporter-safe response of `POST /reports`.
class UserReport {
  const UserReport({
    required this.id,
    required this.reason,
    required this.reasonLabel,
    required this.status,
    required this.statusLabel,
    required this.createdAt,
  });

  factory UserReport.fromJson(Map<String, dynamic> json) {
    return UserReport(
      id: readInt(json, 'id'),
      reason: UserReportReason.fromValue(readString(json, 'reason')),
      reasonLabel: readString(json, 'reason_label'),
      status: UserReportStatus.fromValue(readString(json, 'status')),
      statusLabel: readString(json, 'status_label'),
      createdAt: readDateTime(json, 'created_at'),
    );
  }

  final int id;
  final UserReportReason reason;
  final String reasonLabel;
  final UserReportStatus status;
  final String statusLabel;
  final DateTime createdAt;
}
