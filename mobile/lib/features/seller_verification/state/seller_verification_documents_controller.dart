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

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
