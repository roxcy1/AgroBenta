import 'dart:convert';

import 'package:agrobenta_mobile/core/network/api_client.dart';
import 'package:agrobenta_mobile/services/user_report_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'auth_fakes.dart';

Map<String, dynamic> userReportJson({
  int id = 41,
  String reason = 'harassment',
  String reasonLabel = 'Harassment',
  String status = 'pending',
  String statusLabel = 'Pending',
  String createdAt = '2026-11-18T08:15:00.000000Z',
}) {
  return <String, dynamic>{
    'id': id,
    'reason': reason,
    'reason_label': reasonLabel,
    'status': status,
    'status_label': statusLabel,
    'created_at': createdAt,
  };
}

http.Response userReportCreatedResponse({Map<String, dynamic>? report}) {
  return http.Response(
    jsonEncode(
      successEnvelope(
        message: 'Report submitted.',
        data: report ?? userReportJson(),
      ),
    ),
    201,
    headers: <String, String>{'content-type': 'application/json'},
  );
}

http.Response userReportErrorResponse(int status, Map<String, dynamic> body) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: <String, String>{'content-type': 'application/json'},
  );
}

UserReportService buildUserReportService(
  FakeTokenStore tokenStore,
  Future<http.Response> Function(RecordedRequest request) handler, {
  List<RecordedRequest>? recorded,
}) {
  final ApiClient client = ApiClient(
    tokenStorage: tokenStore,
    httpClient: MockClient((http.Request request) async {
      final RecordedRequest entry = RecordedRequest(request);
      recorded?.add(entry);
      return handler(entry);
    }),
  );
  return UserReportService(client);
}
