import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
import '../../../models/seller_verification.dart';
import '../../../repositories/seller_verification_repository.dart';
import 'seller_verification_documents_state.dart';

/// Presentation logic for the application's evidence documents.
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
/// `Next` is gated on [SellerVerificationDocumentsState.allRequiredUploaded], so a
/// locally-picked file that failed to upload cannot let the user submit an
/// application whose evidence is missing.
class SellerVerificationDocumentsController extends ChangeNotifier {
  SellerVerificationDocumentsController(this._repository);

  final SellerVerificationRepository _repository;

  SellerVerificationDocumentsState _state =
      const SellerVerificationDocumentsState();
  SellerVerificationDocumentsState get state => _state;

  bool _disposed = false;
  final Map<VerificationDocumentType, int> _generations =
      <VerificationDocumentType, int>{};

  /// Seeds historical preview data from an existing rejected record.
  ///
  /// Prior document files remain previewable, but the fresh form starts with
  /// every such slot in `needsUpload`: the backend requires documents to be
  /// newly staged for each new verification record.
  Future<void> seedFrom(SellerVerification? verification) async {
    if (verification == null) {
      return;
    }
    _invalidateAllRequests();
    final SellerVerificationDocumentsState seeded =
        SellerVerificationDocumentsState.fromRecord(verification);
    _set(seeded);

    await Future.wait<void>(
      seeded.all
          .where(
            (VerificationDocument document) =>
                document.hasPreviousRecordDocument,
          )
          .map((VerificationDocument document) => loadPreview(document.type)),
    );
  }

  /// Fetches a previously-uploaded document's bytes once for this form visit.
  ///
  /// The upload status remains `uploaded` for every retrieval outcome. A 404 is
  /// returned by the repository as null; other failures remain visible as a
  /// retryable preview error, except 401 because ApiClient has cleared the token.
  Future<void> loadPreview(VerificationDocumentType type) async {
    if (_disposed || type == VerificationDocumentType.farmPhoto) {
      return;
    }

    final VerificationDocument current = _state.forType(type);
    if (!current.hasPreviousRecordDocument || current.file != null) {
      return;
    }
    if (current.previewStatus == VerificationDocumentPreviewStatus.loading ||
        current.previewStatus == VerificationDocumentPreviewStatus.loaded ||
        current.previewStatus == VerificationDocumentPreviewStatus.missing) {
      return;
    }

    final int generation = _nextGeneration(type);
    _set(
      _state.withDocument(
        current.copyWith(
          previewStatus: VerificationDocumentPreviewStatus.loading,
          clearPreviewBytes: true,
          clearPreviewError: true,
          previewRetryable: false,
        ),
      ),
    );

    try {
      final Uint8List? bytes = await _repository.fetchDocument(type);
      if (!_isCurrentRequest(type, generation)) {
        return;
      }

      final VerificationDocument latest = _state.forType(type);
      if (!latest.hasPreviousRecordDocument || latest.file != null) {
        return;
      }

      _set(
        _state.withDocument(
          latest.copyWith(
            previewStatus: bytes == null || bytes.isEmpty
                ? VerificationDocumentPreviewStatus.missing
                : VerificationDocumentPreviewStatus.loaded,
            previewBytes: bytes == null || bytes.isEmpty ? null : bytes,
            clearPreviewBytes: bytes == null || bytes.isEmpty,
            clearPreviewError: true,
            previewRetryable: false,
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!_isCurrentRequest(type, generation)) {
        return;
      }
      final VerificationDocument latest = _state.forType(type);
      if (!latest.hasPreviousRecordDocument || latest.file != null) {
        return;
      }
      _set(
        _state.withDocument(
          latest.copyWith(
            previewStatus: VerificationDocumentPreviewStatus.failed,
            clearPreviewBytes: true,
            previewError: error.message,
            previewRetryable: !error.requiresReauthentication,
          ),
        ),
      );
    } on Object {
      if (!_isCurrentRequest(type, generation)) {
        return;
      }
      final VerificationDocument latest = _state.forType(type);
      if (!latest.hasPreviousRecordDocument || latest.file != null) {
        return;
      }
      _set(
        _state.withDocument(
          latest.copyWith(
            previewStatus: VerificationDocumentPreviewStatus.failed,
            clearPreviewBytes: true,
            previewError: 'Could not load this document. Please try again.',
            previewRetryable: true,
          ),
        ),
      );
    }
  }

  /// Clears this form's document state when its authenticated account changes.
  ///
  /// Invalidating generations prevents an outstanding upload or preview request
  /// from publishing data from the previous session after the reset.
  void resetForAccountChange() {
    if (_disposed) {
      return;
    }
    _invalidateAllRequests();
    _set(const SellerVerificationDocumentsState());
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

    final int generation = _nextGeneration(type);

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
          if (!_isCurrentRequest(type, generation)) {
            return;
          }
          _set(
            _state.withDocument(
              _state
                  .forType(type)
                  .copyWith(
                    status: VerificationDocumentStatus.uploading,
                    progress: total == 0 ? 0.0 : sent / total,
                  ),
            ),
          );
        },
      );

      if (!_isCurrentRequest(type, generation)) {
        return;
      }

      _set(
        _state.withDocument(
          VerificationDocument(
            type: type,
            status: VerificationDocumentStatus.uploaded,
            file: file,
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!_isCurrentRequest(type, generation)) {
        return;
      }
      _set(
        _state.withDocument(
          _state
              .forType(type)
              .copyWith(
                status: VerificationDocumentStatus.failed,
                clearProgress: true,
                error: error.message,
              ),
        ),
      );
    } on Object {
      if (!_isCurrentRequest(type, generation)) {
        return;
      }
      _set(
        _state.withDocument(
          _state
              .forType(type)
              .copyWith(
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

  /// Reflects document-specific 422 errors from the submission endpoint.
  ///
  /// A prior upload may have succeeded, but the server is authoritative about
  /// what remains staged. Retain the local file for a one-tap re-upload when it
  /// is still available; otherwise the card offers its normal picker action.
  void markDocumentsForReupload(Iterable<VerificationDocumentType> types) {
    if (_disposed) {
      return;
    }

    for (final VerificationDocumentType type in types.toSet()) {
      if (type == VerificationDocumentType.farmPhoto) {
        continue;
      }
      final VerificationDocument current = _state.forType(type);
      _nextGeneration(type);
      _set(
        _state.withDocument(
          current.copyWith(
            status: VerificationDocumentStatus.needsUpload,
            clearProgress: true,
            clearError: true,
            previewStatus: VerificationDocumentPreviewStatus.idle,
            clearPreviewBytes: true,
            clearPreviewError: true,
            previewRetryable: false,
            error: 'Upload this document again before submitting.',
          ),
        ),
      );
    }
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
    final int generation = _nextGeneration(type);
    final bool wasOnServer =
        current.status == VerificationDocumentStatus.uploaded;

    // Clear locally first: the user asked for it gone, and a failed server
    // delete should not leave a thumbnail they cannot get rid of.
    _set(_state.withDocument(VerificationDocument(type: type)));

    if (!wasOnServer) {
      return;
    }

    try {
      await _repository.deleteDocument(type);
      if (!_isCurrentRequest(type, generation)) {
        return;
      }
    } on ApiException catch (error) {
      if (!_isCurrentRequest(type, generation)) {
        return;
      }
      // A 404 means there was nothing staged to delete — the desired end state
      // already holds. Any other failure is surfaced on the slot.
      if (error.kind != ApiErrorKind.notFound && !_disposed) {
        _set(
          _state.withDocument(
            _state
                .forType(type)
                .copyWith(
                  status: VerificationDocumentStatus.failed,
                  error: error.message,
                ),
          ),
        );
      }
    } on Object {
      if (!_isCurrentRequest(type, generation)) {
        return;
      }
      if (!_disposed) {
        _set(
          _state.withDocument(
            _state
                .forType(type)
                .copyWith(
                  status: VerificationDocumentStatus.failed,
                  error: 'Could not remove the document. Please try again.',
                ),
          ),
        );
      }
    }
  }

  /// Adds [file] as a new farm photo and uploads it immediately.
  ///
  /// Refused while another request is in flight, so a photo's position in
  /// the list cannot change while its upload is running.
  Future<void> addFarmPhoto(XFile file) async {
    if (_disposed || !_state.canAddFarmPhoto) {
      return;
    }

    _set(
      _state.copyWith(
        farmPhotos: <VerificationDocument>[
          ..._state.farmPhotos,
          VerificationDocument(
            type: VerificationDocumentType.farmPhoto,
            status: VerificationDocumentStatus.uploading,
            file: file,
          ),
        ],
      ),
    );

    await _uploadFarmPhoto(_state.farmPhotos.length - 1);
  }

  /// Retries the failed farm photo at [index].
  Future<void> retryFarmPhoto(int index) async {
    if (_state.isBusy) {
      return;
    }
    _replaceFarmPhoto(
      index,
      _state.farmPhotos[index].copyWith(
        status: VerificationDocumentStatus.uploading,
        clearError: true,
      ),
    );
    await _uploadFarmPhoto(index);
  }

  /// Removes the farm photo at [index], from the server too if it was stored.
  ///
  /// A photo the server still holds stays in the list until it is really gone,
  /// because it would otherwise be submitted without the user seeing it.
  Future<void> removeFarmPhoto(int index) async {
    if (_state.isBusy) {
      return;
    }

    final VerificationDocument photo = _state.farmPhotos[index];

    if (photo.photoId != null) {
      _replaceFarmPhoto(
        index,
        photo.copyWith(
          status: VerificationDocumentStatus.uploading,
          clearError: true,
        ),
      );

      try {
        await _repository.deleteFarmPhoto(photo.photoId!);
      } on Object catch (error) {
        final bool alreadyGone =
            error is ApiException && error.kind == ApiErrorKind.notFound;
        if (!alreadyGone) {
          _replaceFarmPhoto(
            index,
            photo.copyWith(
              error: 'Could not remove the photo. Please try again.',
            ),
          );
          return;
        }
      }
    }

    _set(
      _state.copyWith(
        farmPhotos: <VerificationDocument>[..._state.farmPhotos]
          ..removeAt(index),
      ),
    );
  }

  Future<void> _uploadFarmPhoto(int index) async {
    final VerificationDocument photo = _state.farmPhotos[index];

    try {
      final String photoId = await _repository.uploadFarmPhoto(
        file: photo.file!,
      );
      _replaceFarmPhoto(
        index,
        VerificationDocument(
          type: VerificationDocumentType.farmPhoto,
          status: VerificationDocumentStatus.uploaded,
          file: photo.file,
          photoId: photoId,
        ),
      );
    } on Object catch (error) {
      _replaceFarmPhoto(
        index,
        photo.copyWith(
          status: VerificationDocumentStatus.failed,
          error: error is ApiException
              ? error.message
              : 'Upload failed. Please try again.',
        ),
      );
    }
  }

  void _replaceFarmPhoto(int index, VerificationDocument photo) {
    if (_disposed) {
      return;
    }
    _set(
      _state.copyWith(
        farmPhotos: <VerificationDocument>[..._state.farmPhotos]
          ..[index] = photo,
      ),
    );
  }

  void _set(SellerVerificationDocumentsState next) {
    if (_disposed) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  int _nextGeneration(VerificationDocumentType type) {
    final int next = (_generations[type] ?? 0) + 1;
    _generations[type] = next;
    return next;
  }

  bool _isCurrentRequest(VerificationDocumentType type, int generation) =>
      !_disposed && _generations[type] == generation;

  void _invalidateAllRequests() {
    for (final VerificationDocumentType type
        in VerificationDocumentType.values) {
      _nextGeneration(type);
    }
  }

  @override
  void dispose() {
    _invalidateAllRequests();
    _disposed = true;
    _state = const SellerVerificationDocumentsState();
    super.dispose();
  }
}
