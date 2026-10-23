import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../core/constants/api_constants.dart';
import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../models/seller_verification.dart';

/// The seller verification API surface.
///
/// Two methods, one per endpoint, and nothing else — no token handling, no
/// persistence, no error translation. Those belong to
/// `SellerVerificationRepository`.
///
/// ## What this service can and cannot send
///
/// [submit] is the only place in the app that writes a request body, so it is
/// the one place a server-owned field could leak out. The body is an explicit
/// allow-list of [SellerVerificationEndpoints.writableFields], which is exactly
/// what `SubmitSellerVerificationRequest` validates. The fields the backend
/// derives — `user_id`, `status`, `submitted_at`, `admin_note`, `reviewed_by` —
/// and the two authority fields `role` and `seller_capability` are not merely
/// unused here, they are **unreachable**: there is no code path from a form
/// field to a key in this body.
///
/// `seller_capability` in particular is the hinge of the single-account model.
/// This app cannot grant it, and a `{"seller_capability": "seller"}` in a
/// request body would bypass the entire verification workflow
/// (functional documentation §2.6). The backend answers `422` if a client tries;
/// the guarantee here is that this client never does.
class SellerVerificationService {
  const SellerVerificationService(this._apiClient);

  final ApiClient _apiClient;

  /// `GET /seller-verification/me` — the caller's most recent verification.
  ///
  /// A single record, never a list: the server resolves "most recent" by
  /// `submitted_at desc, id desc` so the client is not left picking the newest
  /// of several (contract §5.3).
  ///
  /// Throws [ApiException]:
  ///  * [ApiErrorKind.notFound] when the user has never submitted. **This is
  ///    the normal first state, not a failure** — the screen turns it into "you
  ///    have not applied yet" rather than an error. It is still an exception
  ///    because from the transport's point of view a missing record genuinely is
  ///    a 404, and quietly returning null for a *malformed* response too would
  ///    make those two indistinguishable.
  ///  * [ApiErrorKind.unauthorized] on a `401`; the token has already been
  ///    cleared and the app is signed out.
  Future<SellerVerification> current() {
    return _apiClient.get<SellerVerification>(
      SellerVerificationEndpoints.mine,
      parse: (Object? data) => SellerVerification.fromJson(
        _asObject(data, 'GET /seller-verification/me'),
      ),
    );
  }

  /// `POST /seller-verification` — file a verification.
  ///
  /// Blank optional fields are omitted rather than sent empty, so a submission
  /// with only a business name carries one key. The server treats `null` and
  /// absent identically, but an empty string is stored, and `""` is not the same
  /// thing as "not provided" when a human later reads the review queue.
  ///
  /// Throws [ApiException]:
  ///  * [ApiErrorKind.conflict] on a `409` — a verification is already open.
  ///    The user did nothing wrong and retrying will not help until an
  ///    administrator decides, so the screen must not present this as a
  ///    validation error.
  ///  * [ApiErrorKind.forbidden] on a `403` — the account is already an approved
  ///    seller, so there is nothing to submit.
  ///  * [ApiErrorKind.validation] on a `422`, carrying per-field messages.
  ///  * [ApiErrorKind.rateLimited] on a `429`; the route is throttled to 5/min.
  Future<SellerVerification> submit({
    required String businessName,
    String? businessLocation,
    String? businessDescription,
    String? idDocumentRef,
  }) {
    return _apiClient.post<SellerVerification>(
      SellerVerificationEndpoints.submit,
      body: <String, dynamic>{
        // Explicit allow-list, in the order the contract lists them. Anything a
        // form adds later has to be named here to be sent.
        'business_name': businessName.trim(),
        if (_present(businessLocation))
          'business_location': businessLocation!.trim(),
        if (_present(businessDescription))
          'business_description': businessDescription!.trim(),
        if (_present(idDocumentRef)) 'id_document_ref': idDocumentRef!.trim(),
      },
      parse: (Object? data) => SellerVerification.fromJson(
        _asObject(data, 'POST /seller-verification'),
      ),
    );
  }

  static bool _present(String? value) =>
      value != null && value.trim().isNotEmpty;

  /// `POST /seller-verification/documents` — stage one evidence document.
  ///
  /// [file] is the picked image. The body is a multipart form with exactly two
  /// parts: `type` (the enum's wire value) and `document` (the bytes). Both are
  /// named here, so a server-owned field — `user_id`, `seller_verification_id`,
  /// `path`, `status`, all `prohibited` server-side — has no path into the
  /// request.
  ///
  /// There is no `data` payload beyond `{ type, uploaded: true }`; the stored
  /// path is never returned, because the file is on a private disk and is read
  /// back only through [fetchDocument]. The return value is discarded.
  ///
  /// Throws [ApiException]:
  ///  * `validation` on a `422` — the file failed the mime/size rules.
  ///  * `forbidden` on a `403` — the account is already an approved seller.
  ///  * `conflict` on a `409` — an application is already open for review.
  Future<void> uploadDocument({
    required VerificationDocumentType type,
    required XFile file,
    void Function(int sent, int total)? onProgress,
  }) async {
    final int length = await file.length();
    int uploaded = 0;

    final http.MultipartFile part = http.MultipartFile(
      SellerVerificationEndpoints.documentFileField,
      _wrapWithProgress(file.openRead(), (int chunk) {
        uploaded += chunk;
        onProgress?.call(uploaded, length);
      }),
      length,
      filename: file.name,
    );

    return _apiClient.postMultipart<void>(
      path: SellerVerificationEndpoints.documents,
      files: <http.MultipartFile>[part],
      fields: <String, String>{'type': type.value},
      parse: (_) {},
    );
  }

  /// `DELETE /seller-verification/documents/{type}` — remove a staged document.
  ///
  /// Only the staging area is mutable; once an application is submitted its
  /// documents belong to the record under review and this route does not reach
  /// them.
  ///
  /// Throws [ApiException]:
  ///  * `notFound` on a `404` — there is no staged document of that type.
  Future<void> deleteDocument(VerificationDocumentType type) {
    return _apiClient.delete<void>(
      SellerVerificationEndpoints.deleteDocument(type.value),
      parse: (_) {},
    );
  }

  /// `GET /seller-verification/documents/{type}` — the stored document's bytes.
  ///
  /// The success body is the file itself, not an envelope, so this goes through
  /// [ApiClient.getBytes]. Returns the bytes, or `null` for a `404` — the
  /// document has never been uploaded — which the caller renders as "not on
  /// file" rather than as a failure. Every other [ApiException] propagates.
  Future<Uint8List?> fetchDocument(VerificationDocumentType type) async {
    try {
      return await _apiClient.getBytes(
        SellerVerificationEndpoints.document(type.value),
      );
    } on ApiException catch (error) {
      if (error.kind == ApiErrorKind.notFound) {
        return null;
      }
      rethrow;
    }
  }

  /// Wraps [stream] so each emitted chunk is reported to [onBytes] before being
  /// forwarded, letting callers track upload progress.
  static Stream<List<int>> _wrapWithProgress(
    Stream<List<int>> stream,
    void Function(int bytes) onBytes,
  ) async* {
    await for (final List<int> chunk in stream) {
      onBytes(chunk.length);
      yield chunk;
    }
  }

  /// Casts an unwrapped `data` payload to a JSON object with a message that
  /// names the endpoint, instead of a bare cast error. A [FormatException] here
  /// is translated by `ApiClient` into [ApiErrorKind.malformedResponse].
  static Map<String, dynamic> _asObject(Object? data, String context) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return data.cast<String, dynamic>();
    }
    throw FormatException(
      'Expected the $context response data to be a JSON object, got '
      '${data.runtimeType}.',
    );
  }
}
