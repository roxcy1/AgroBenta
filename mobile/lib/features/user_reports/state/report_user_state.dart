import '../../../models/user_report.dart';

enum ReportUserStatus { idle, submitting, submitted, failed }

/// Immutable presentation state for one report form.
class ReportUserState {
  const ReportUserState({
    this.status = ReportUserStatus.idle,
    this.errorMessage,
    this.fieldErrors = const <String, List<String>>{},
    this.report,
  });

  final ReportUserStatus status;
  final String? errorMessage;
  final Map<String, List<String>> fieldErrors;
  final UserReport? report;

  bool get isSubmitting => status == ReportUserStatus.submitting;

  ReportUserState copyWith({
    ReportUserStatus? status,
    String? errorMessage,
    Map<String, List<String>>? fieldErrors,
    UserReport? report,
    bool clearError = false,
  }) {
    return ReportUserState(
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      fieldErrors: clearError
          ? const <String, List<String>>{}
          : (fieldErrors ?? this.fieldErrors),
      report: report ?? this.report,
    );
  }
}
