import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
import '../../../models/user_report.dart';
import '../../../repositories/user_report_repository.dart';
import 'report_user_state.dart';

/// Presentation logic for one report submission.
class ReportUserController extends ChangeNotifier {
  ReportUserController(this._repository, this.reportedUserId);

  final UserReportRepository _repository;
  final int reportedUserId;

  ReportUserState _state = const ReportUserState();
  ReportUserState get state => _state;

  bool _disposed = false;

  Future<bool> submit({
    required UserReportReason reason,
    required String description,
    XFile? evidence,
  }) async {
    if (_state.isSubmitting) {
      return false;
    }

    _set(_state.copyWith(
      status: ReportUserStatus.submitting,
      clearError: true,
    ));

    try {
      final UserReport report = await _repository.submit(
        reportedUserId: reportedUserId,
        reason: reason,
        description: description,
        evidence: evidence,
      );

      if (_disposed) {
        return false;
      }

      _set(ReportUserState(
        status: ReportUserStatus.submitted,
        report: report,
      ));

      return true;
    } on ApiException catch (error) {
      if (_disposed) {
        return false;
      }

      _set(ReportUserState(
        status: ReportUserStatus.failed,
        errorMessage: _messageFor(error),
        fieldErrors: error.kind == ApiErrorKind.validation
            ? error.validationErrors
            : const <String, List<String>>{},
      ));

      return false;
    } on Object {
      if (_disposed) {
        return false;
      }

      _set(const ReportUserState(
        status: ReportUserStatus.failed,
        errorMessage: 'Something went wrong. Please try again.',
      ));

      return false;
    }
  }

  String _messageFor(ApiException error) {
    return switch (error.kind) {
      ApiErrorKind.validation =>
        error.message.isEmpty
            ? 'Please check the highlighted fields.'
            : error.message,
      ApiErrorKind.conflict =>
        error.message.isEmpty
            ? 'You already have a pending report about this user.'
            : error.message,
      ApiErrorKind.rateLimited =>
        'Too many reports were submitted. Please wait a moment and try again.',
      ApiErrorKind.forbidden =>
        error.message.isEmpty
            ? 'This account cannot be reported.'
            : error.message,
      ApiErrorKind.notFound => 'This account is no longer available.',
      ApiErrorKind.network =>
        'Could not reach the server. Please check your connection and try again.',
      ApiErrorKind.unauthorized => 'Please sign in again to submit a report.',
      ApiErrorKind.server =>
        'The server could not save the report. Please try again later.',
      ApiErrorKind.malformedResponse =>
        'The server returned an unexpected response. Please try again later.',
    };
  }

  void _set(ReportUserState state) {
    if (_disposed) {
      return;
    }
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
