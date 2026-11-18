import 'package:agrobenta_mobile/core/network/api_exception.dart';
import 'package:agrobenta_mobile/features/user_reports/state/report_user_controller.dart';
import 'package:agrobenta_mobile/features/user_reports/state/report_user_state.dart';
import 'package:agrobenta_mobile/models/user_report.dart';
import 'package:agrobenta_mobile/repositories/user_report_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import '../../support/user_report_fakes.dart';

class _FakeUserReportRepository implements UserReportRepository {
  _FakeUserReportRepository(this.result);

  Future<UserReport> Function() result;
  int calls = 0;

  @override
  Future<UserReport> submit({
    required int reportedUserId,
    required UserReportReason reason,
    required String description,
    XFile? evidence,
  }) {
    calls++;
    return result();
  }
}

void main() {
  test('publishes submitted state and the created report', () async {
    final repository = _FakeUserReportRepository(
      () async => UserReport.fromJson(userReportJson()),
    );
    final controller = ReportUserController(repository, 22);
    addTearDown(controller.dispose);

    final bool submitted = await controller.submit(
      reason: UserReportReason.harassment,
      description: 'Repeated abusive messages.',
    );

    expect(submitted, isTrue);
    expect(controller.state.status, ReportUserStatus.submitted);
    expect(controller.state.report?.id, 41);
    expect(repository.calls, 1);
  });

  test('validation errors are exposed per field', () async {
    final repository = _FakeUserReportRepository(
      () async => throw const ApiException(
        kind: ApiErrorKind.validation,
        message: 'Please check the highlighted fields.',
        statusCode: 422,
        validationErrors: <String, List<String>>{
          'description': <String>['Describe the incident in at least 10 characters.'],
        },
      ),
    );
    final controller = ReportUserController(repository, 22);
    addTearDown(controller.dispose);

    final bool submitted = await controller.submit(
      reason: UserReportReason.other,
      description: 'short',
    );

    expect(submitted, isFalse);
    expect(controller.state.status, ReportUserStatus.failed);
    expect(controller.state.fieldErrors['description'], isNotEmpty);
  });

  test('duplicate and rate-limit failures are presented honestly', () async {
    final repository = _FakeUserReportRepository(
      () async => throw const ApiException(
        kind: ApiErrorKind.conflict,
        message: 'You already have a pending report about this user.',
        statusCode: 409,
      ),
    );
    final controller = ReportUserController(repository, 22);
    addTearDown(controller.dispose);

    await controller.submit(
      reason: UserReportReason.harassment,
      description: 'Repeated abusive messages.',
    );
    expect(
      controller.state.errorMessage,
      'You already have a pending report about this user.',
    );

    repository.result = () async => throw const ApiException(
      kind: ApiErrorKind.rateLimited,
      message: 'Too Many Attempts.',
      statusCode: 429,
    );

    await controller.submit(
      reason: UserReportReason.harassment,
      description: 'Repeated abusive messages.',
    );
    expect(controller.state.errorMessage, contains('Too many reports'));
  });
}
