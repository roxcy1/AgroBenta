import 'dart:typed_data';

import 'package:agrobenta_mobile/core/constants/api_constants.dart';
import 'package:agrobenta_mobile/models/user_report.dart';
import 'package:agrobenta_mobile/services/user_report_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../support/auth_fakes.dart';
import '../support/user_report_fakes.dart';

void main() {
  late FakeTokenStore tokenStore;
  late List<RecordedRequest> recorded;
  late UserReportService service;

  UserReportService build(
    Future<http.Response> Function(RecordedRequest request) handler,
  ) => buildUserReportService(tokenStore, handler, recorded: recorded);

  setUp(() {
    tokenStore = FakeTokenStore('1|mobile-token');
    recorded = <RecordedRequest>[];
    service = build((_) async => userReportCreatedResponse());
  });

  test('posts to /reports with the bearer token and no evidence', () async {
    final UserReport report = await service.submit(
      reportedUserId: 22,
      reason: UserReportReason.scamFraud,
      description: 'Asked for payment outside the platform.',
    );

    expect(report.id, 41);
    expect(recorded, hasLength(1));
    expect(recorded.single.method, 'POST');
    expect(recorded.single.apiPath, UserReportEndpoints.create);
    expect(recorded.single.authorization, 'Bearer 1|mobile-token');

    final String body = recorded.single.request.body;
    expect(body, contains('name="reported_user_id"'));
    expect(body, contains('22'));
    expect(body, contains('name="reason"'));
    expect(body, contains('scam_fraud'));
    expect(body, contains('name="description"'));
    expect(body, contains('Asked for payment outside the platform.'));
    expect(body, isNot(contains('reporter_id')));
    expect(body, isNot(contains('status')));
  });

  test('attaches exactly one optional evidence file', () async {
    final XFile evidence = XFile.fromData(
      Uint8List.fromList(<int>[1, 2, 3, 4]),
      name: 'evidence.jpg',
      mimeType: 'image/jpeg',
    );
    await service.submit(
      reportedUserId: 22,
      reason: UserReportReason.other,
      description: 'Suspicious behaviour in a transaction.',
      evidence: evidence,
    );

    final String body = recorded.single.request.body;
    expect(body, contains('name="evidence"'));
    expect(body, contains('filename="evidence-upload.jpg"'));
  });

  test('passes a 409 duplicate response through as a conflict', () async {
    service = build(
      (_) async => userReportErrorResponse(409, <String, dynamic>{
        'message': 'You already have a pending report about this user.',
      }),
    );

    await expectLater(
      service.submit(
        reportedUserId: 22,
        reason: UserReportReason.harassment,
        description: 'Repeated abusive messages.',
      ),
      throwsA(
        isA<Exception>().having(
          (Exception error) => error.toString(),
          'message',
          contains('pending report'),
        ),
      ),
    );
  });
}
