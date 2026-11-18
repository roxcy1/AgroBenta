import 'package:agrobenta_mobile/core/network/api_exception.dart';
import 'package:agrobenta_mobile/core/theme/app_theme.dart';
import 'package:agrobenta_mobile/features/user_reports/state/user_report_scope.dart';
import 'package:agrobenta_mobile/features/user_reports/view/report_user_screen.dart';
import 'package:agrobenta_mobile/models/user_report.dart';
import 'package:agrobenta_mobile/repositories/user_report_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import '../../support/user_report_fakes.dart';

class _FakeRepository implements UserReportRepository {
  _FakeRepository({this.error});

  ApiException? error;
  int calls = 0;
  UserReportReason? lastReason;
  String? lastDescription;

  @override
  Future<UserReport> submit({
    required int reportedUserId,
    required UserReportReason reason,
    required String description,
    XFile? evidence,
  }) async {
    calls++;
    lastReason = reason;
    lastDescription = description;
    if (error != null) {
      throw error!;
    }
    return UserReport.fromJson(userReportJson());
  }
}

class _Launcher extends StatelessWidget {
  const _Launcher({
    required this.repository,
    required this.currentUserId,
    required this.reportedUserId,
  });

  final UserReportRepository repository;
  final int currentUserId;
  final int reportedUserId;

  @override
  Widget build(BuildContext context) {
    return UserReportScope(
      repository: repository,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) => ReportUserScreen(
                      reportedUserId: reportedUserId,
                      reportedUserName: 'Reported User',
                      reportedUserRole: 'Seller',
                      currentUserId: currentUserId,
                    ),
                  ),
                ),
                child: const Text('Open report'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _openForm(
  WidgetTester tester, {
  required _FakeRepository repository,
  int currentUserId = 7,
  int reportedUserId = 22,
}) async {
  await tester.pumpWidget(
    _Launcher(
      repository: repository,
      currentUserId: currentUserId,
      reportedUserId: reportedUserId,
    ),
  );
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.tap(find.text('Open report'));
  await tester.pumpAndSettle();
}

Future<void> _fillAndSubmit(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButtonFormField<UserReportReason>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Harassment').last);
  await tester.pumpAndSettle();

  await tester.enterText(
    find.byType(TextFormField),
    'Repeated abusive messages after an inquiry.',
  );
  await tester.tap(find.widgetWithText(FilledButton, 'Submit Report'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Submit Report').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the reported identity and requires reason and description', (
    WidgetTester tester,
  ) async {
    final repository = _FakeRepository();
    await _openForm(tester, repository: repository);

    expect(find.text('Report User'), findsOneWidget);
    expect(find.text('Reported User'), findsOneWidget);
    expect(find.text('Seller'), findsOneWidget);
    expect(find.text('Reason'), findsOneWidget);
    expect(find.text('What happened?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Submit Report'));
    await tester.pumpAndSettle();

    expect(find.text('Select a reason.'), findsOneWidget);
    expect(
      find.text('Describe the incident in at least 10 characters.'),
      findsOneWidget,
    );
    expect(repository.calls, 0);
  });

  testWidgets('submits the approved reason and description through confirmation', (
    WidgetTester tester,
  ) async {
    final repository = _FakeRepository();
    await _openForm(tester, repository: repository);
    await _fillAndSubmit(tester);

    expect(find.text('Submit this report?'), findsNothing);
    expect(repository.calls, 1);
    expect(repository.lastReason, UserReportReason.harassment);
    expect(
      repository.lastDescription,
      'Repeated abusive messages after an inquiry.',
    );
    expect(
      find.text('Report submitted for administrator review.'),
      findsOneWidget,
    );
  });

  testWidgets('blocks self-reporting before submission', (
    WidgetTester tester,
  ) async {
    final repository = _FakeRepository();
    await _openForm(
      tester,
      repository: repository,
      currentUserId: 22,
      reportedUserId: 22,
    );

    expect(find.text('You cannot report your own account.'), findsOneWidget);
    final FilledButton submit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Submit Report'),
    );
    expect(submit.onPressed, isNull);
    expect(repository.calls, 0);
  });

  testWidgets('shows the duplicate-report conflict returned by the server', (
    WidgetTester tester,
  ) async {
    final repository = _FakeRepository(
      error: const ApiException(
        kind: ApiErrorKind.conflict,
        message: 'You already have a pending report about this user.',
        statusCode: 409,
      ),
    );
    await _openForm(tester, repository: repository);
    await _fillAndSubmit(tester);

    expect(
      find.text('You already have a pending report about this user.'),
      findsOneWidget,
    );
    expect(find.text('Report User'), findsOneWidget);
  });
}
