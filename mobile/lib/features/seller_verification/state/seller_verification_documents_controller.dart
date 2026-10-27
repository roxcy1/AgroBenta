import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
import '../../../models/seller_verification.dart';
import '../../../repositories/seller_verification_repository.dart';
import 'seller_verification_documents_state.dart';

/// Presentation logic for the two required evidence documents.
///
/// Owned by the form screen and disposed with it, because a picked file and its
/// upload progress are scoped to one visit to the form — not to the whole app,
/// unlike the status [SellerVerificationController]. It reaches the same
/// repository through `SellerVerificationScope`.
///
/// ## The rule this class exists to enforce
///
/// **A green "uploaded" state means the server stored the file.** Picking a file
/// moves a slot to `selected`; only a `201` from
/// `POST /seller-verification/documents` moves it to `uploaded`. The step's
/// `Next` is gated on [SellerVerificationDocumentsState.bothUploaded], so a
/// locally-picked file that failed to upload cannot let the user submit an
/// application whose evidence is missing.
class SellerVerificationDocumentsController extends ChangeNotifier {
  SellerVerificationDocumentsController(this._repository);

  final SellerVerificationRepository _repository;

  SellerVerificationDocumentsState _state =
      const SellerVerificationDocumentsState();
  SellerVerificationDocumentsState get state => _state;

  bool _disposed = false;

  /// Seeds the slots from an existing record, so a resubmission shows which
  /// documents the server already holds before any upload happens.
  void seedFrom(SellerVerification? verification) {
    if (verification == null) {
      return;
    }
    _set(SellerVerificationDocumentsState.fromRecord(verification));
  }

  /// Picks [file] for [type] and uploads it immediately.
  ///
  /// Uploading on pick, rather than on `Next`, is what lets the card report an
  /// honest state per document: "uploading", then "uploaded", or a failure the
  /// user can retry without losing the file.
  Future<void> pickAndUpload({
    required VerificationDocumentType type,
    required XFile file,
  }) async {
    if (_disposed) {
      return;
    }

    _set(
      _state.withDocument(
        VerificationDocument(
          type: type,
          status: VerificationDocumentStatus.uploading,
          file: file,
          progress: 0.0,
        ),
      ),
    );

    try {
      await _repository.uploadDocument(
        type: type,
        file: file,
        onProgress: (int sent, int total) {
          if (_disposed) {
            return;
          }
          _set(
            _state.withDocument(
              _state.forType(type).copyWith(
                status: VerificationDocumentStatus.uploading,
                progress: total == 0 ? 0.0 : sent / total,
              ),
            ),
          );
        },
      );

      if (_disposed) {
        return;
      }

      _set(
        _state.withDocument(
          VerificationDocument(
            type: type,
            status: VerificationDocumentStatus.uploaded,
          ),
        ),
      );
    } on ApiException catch (error) {
      if (_disposed) {
        return;
      }
      _set(
        _state.withDocument(
          _state.forType(type).copyWith(
            status: VerificationDocumentStatus.failed,
            clearProgress: true,
            error: error.message,
          ),
        ),
      );
    } on Object {
      if (_disposed) {
        return;
      }
      _set(
        _state.withDocument(
          _state.forType(type).copyWith(
            status: VerificationDocumentStatus.failed,
            clearProgress: true,
            error: 'Upload failed. Please try again.',
          ),
        ),
      );
    }
  }

  /// Retries the upload of the file already picked for [type].
  ///
  /// Does nothing when there is no local file — a slot seeded from a record has
  /// no bytes to re-send, and the record already reports the document on file.
  Future<void> retry(VerificationDocumentType type) async {
    final XFile? file = _state.forType(type).file;
    if (file == null) {
      return;
    }
    await pickAndUpload(type: type, file: file);
  }

  /// Removes a document the user chose locally, or clears a staged one on the
  /// server.
  ///
  /// A slot that was never uploaded only has to be cleared locally. A slot the
  /// server has staged (or that a resubmission inherited from a record) is
  /// removed through the API; a `404` means it was already gone and is treated
  /// as success so the UI still clears.
  Future<void> remove(VerificationDocumentType type) async {
    final VerificationDocument current = _state.forType(type);
    final bool wasOnServer =
        current.status == VerificationDocumentStatus.uploaded;

    // Clear locally first: the user asked for it gone, and a failed server
    // delete should not leave a thumbnail they cannot get rid of.
    _set(
      _state.withDocument(
        VerificationDocument(type: type),
      ),
    );

    if (!wasOnServer) {
      return;
    }

    try {
      await _repository.deleteDocument(type);
    } on ApiException catch (error) {
      // A 404 means there was nothing staged to delete — the desired end state
      // already holds. Any other failure is surfaced on the slot.
      if (error.kind != ApiErrorKind.notFound && !_disposed) {
        _set(
          _state.withDocument(
            _state.forType(type).copyWith(
              status: VerificationDocumentStatus.failed,
              error: error.message,
            ),
          ),
        );
      }
    } on Object {
      if (!_disposed) {
        _set(
          _state.withDocument(
            _state.forType(type).copyWith(
              status: VerificationDocumentStatus.failed,
              error: 'Could not remove the document. Please try again.',
            ),
          ),
        );
      }
    }
  }

  void _set(SellerVerificationDocumentsState next) {
    if (_disposed) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
