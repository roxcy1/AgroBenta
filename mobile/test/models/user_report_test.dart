import 'package:agrobenta_mobile/models/user_report.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/user_report_fakes.dart';

void main() {
  test('parses the reporter-safe create response', () {
    final UserReport report = UserReport.fromJson(userReportJson());

    expect(report.id, 41);
    expect(report.reason, UserReportReason.harassment);
    expect(report.reasonLabel, 'Harassment');
    expect(report.status, UserReportStatus.pending);
    expect(report.statusLabel, 'Pending');
    expect(report.createdAt.isUtc, isFalse);
  });

  test('the six approved reasons keep their exact wire values and labels', () {
    expect(
      UserReportReason.values.map((UserReportReason reason) => reason.value),
      <String>[
        'scam_fraud',
        'harassment',
        'misleading_information',
        'spam_suspicious_activity',
        'inappropriate_content',
        'other',
      ],
    );
    expect(UserReportReason.scamFraud.label, 'Scam/Fraud');
    expect(
      UserReportReason.spamSuspiciousActivity.label,
      'Spam/Suspicious Activity',
    );
  });

  test('unknown reason and status fail loudly', () {
    expect(
      () => UserReportReason.fromValue('unknown'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => UserReportStatus.fromValue('unknown'),
      throwsA(isA<FormatException>()),
    );
  });
}
