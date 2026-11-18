import 'package:image_picker/image_picker.dart';

import '../models/user_report.dart';
import '../services/user_report_service.dart';

/// Thin orchestration over [UserReportService].
///
/// No error translation: the controller branches on `ApiException.kind` so the
/// 422/409/429 outcomes keep the server's own meaning.
class UserReportRepository {
  const UserReportRepository(this._service);

  final UserReportService _service;

  Future<UserReport> submit({
    required int reportedUserId,
    required UserReportReason reason,
    required String description,
    XFile? evidence,
  }) {
    return _service.submit(
      reportedUserId: reportedUserId,
      reason: reason,
      description: description,
      evidence: evidence,
    );
  }
}
