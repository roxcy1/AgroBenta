import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../core/constants/api_constants.dart';
import '../core/network/api_client.dart';
import '../models/user_report.dart';

/// The mobile user-report transport.
///
/// The reporter is the bearer token; this service sends only the reported user,
/// the approved reason, the description and one optional screenshot. Moderation
/// fields and account status have no path into this body.
class UserReportService {
  const UserReportService(this._client);

  final ApiClient _client;

  Future<UserReport> submit({
    required int reportedUserId,
    required UserReportReason reason,
    required String description,
    XFile? evidence,
  }) async {
    final List<http.MultipartFile> files = <http.MultipartFile>[];

    if (evidence != null) {
      final Uint8List bytes = await evidence.readAsBytes();
      files.add(
        http.MultipartFile.fromBytes(
          UserReportEndpoints.evidenceField,
          bytes,
          filename: _filenameFor(evidence),
        ),
      );
    }

    return _client.postMultipart<UserReport>(
      path: UserReportEndpoints.create,
      fields: <String, String>{
        'reported_user_id': '$reportedUserId',
        'reason': reason.value,
        'description': description.trim(),
      },
      files: files,
      parse: (Object? data) => UserReport.fromJson(_asObject(data)),
    );
  }

  static String _filenameFor(XFile evidence) {
    final String name = evidence.name.trim();
    if (name.contains('.')) {
      return name;
    }

    return switch (evidence.mimeType) {
      'image/png' => 'evidence-upload.png',
      'image/webp' => 'evidence-upload.webp',
      _ => 'evidence-upload.jpg',
    };
  }

  static Map<String, dynamic> _asObject(Object? data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return data.cast<String, dynamic>();
    }
    throw const FormatException(
      'Expected a JSON object for a user report resource.',
    );
  }
}
