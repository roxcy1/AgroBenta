import 'package:image_picker/image_picker.dart';

import '../../../models/seller_verification.dart';

/// The lifecycle of one required evidence document in the application form.
///
/// Mirrors the honest upload states doc 03 requires: a picked file is *selected
/// locally*, never *uploaded*, until the server has confirmed it. A green
/// "uploaded" state is only reached after `POST /seller-verification/documents`
/// answered `201`.
enum VerificationDocumentStatus {
  /// Nothing chosen yet.
  empty,

  /// Picked locally, not yet sent.
  selected,

  /// The upload request is in flight.
  uploading,

  /// The server confirmed and stored it.
  uploaded,

  /// The upload was refused or failed; retryable.
  failed,
}

/// One document slot's state: the picked file, its upload status, progress and
/// the last failure message.
///
/// Immutable, like `ListingPhotoItem`, so the controller can publish a new value
/// and a `ListenableBuilder` can diff cheaply.
class VerificationDocument {
  const VerificationDocument({
    required this.type,
    this.status = VerificationDocumentStatus.empty,
    this.file,
    this.progress,
    this.error,
  });

  /// Which of the two required documents this slot holds.
  final VerificationDocumentType type;

  final VerificationDocumentStatus status;

  /// The locally-picked file, while one is selected or uploading.
  final XFile? file;

  /// Upload progress from 0.0 to 1.0 while [status] is [uploading].
  final double? progress;

  /// A displayable failure while [status] is [failed].
  final String? error;

  /// Whether the server has confirmed this document is stored.
  bool get isUploaded => status == VerificationDocumentStatus.uploaded;

  /// Whether a file is present on the device for this slot.
  bool get hasFile => file != null;

  /// Whether the slot is busy with a request of ours.
  bool get isUploading => status == VerificationDocumentStatus.uploading;

  VerificationDocument copyWith({
    VerificationDocumentStatus? status,
    XFile? file,
    double? progress,
    String? error,
    bool clearFile = false,
    bool clearError = false,
    bool clearProgress = false,
  }) {
    return VerificationDocument(
      type: type,
      status: status ?? this.status,
      file: clearFile ? null : (file ?? this.file),
      progress: clearProgress ? null : (progress ?? this.progress),
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  String toString() =>
      'VerificationDocument(${type.value}, ${status.name}, ${file?.name})';
}

/// An immutable snapshot of both required document slots.
class SellerVerificationDocumentsState {
  const SellerVerificationDocumentsState({
    this.idDocument = const VerificationDocument(
      type: VerificationDocumentType.idDocument,
    ),
    this.selfie = const VerificationDocument(
      type: VerificationDocumentType.selfie,
    ),
  });

  final VerificationDocument idDocument;
  final VerificationDocument selfie;

  /// The slot for one document type.
  VerificationDocument forType(VerificationDocumentType type) =>
      type == VerificationDocumentType.idDocument ? idDocument : selfie;

  /// The two slots, in the order they appear on screen.
  List<VerificationDocument> get all => <VerificationDocument>[
    idDocument,
    selfie,
  ];

  /// Whether both documents are stored on the server.
  ///
  /// This is what gates the step's `Next`: a locally-picked file is not enough,
  /// because the submission endpoint requires both files to be staged.
  bool get bothUploaded => idDocument.isUploaded && selfie.isUploaded;

  /// Whether either slot has an upload in flight.
  bool get isBusy => idDocument.isUploading || selfie.isUploading;

  SellerVerificationDocumentsState copyWith({
    VerificationDocument? idDocument,
    VerificationDocument? selfie,
  }) {
    return SellerVerificationDocumentsState(
      idDocument: idDocument ?? this.idDocument,
      selfie: selfie ?? this.selfie,
    );
  }

  /// A new state with one slot replaced, chosen by its type.
  SellerVerificationDocumentsState withDocument(VerificationDocument document) =>
      document.type == VerificationDocumentType.idDocument
      ? copyWith(idDocument: document)
      : copyWith(selfie: document);

  /// Seeds the two slots as already uploaded, from a record that reports the
  /// documents are on file with no locally-picked file.
  ///
  /// Used when opening a resubmission, so the flow knows which files the server
  /// already holds. There is no local file to preview in this state — the bytes
  /// live behind the authenticated fetch endpoint.
  static SellerVerificationDocumentsState fromRecord(
    SellerVerification verification,
  ) {
    VerificationDocument slot(
      VerificationDocumentType type,
      bool present,
    ) => VerificationDocument(
      type: type,
      status: present
          ? VerificationDocumentStatus.uploaded
          : VerificationDocumentStatus.empty,
    );

    return SellerVerificationDocumentsState(
      idDocument: slot(
        VerificationDocumentType.idDocument,
        verification.hasIdDocument,
      ),
      selfie: slot(VerificationDocumentType.selfie, verification.hasSelfie),
    );
  }

  @override
  String toString() =>
      'SellerVerificationDocumentsState(${idDocument.status.name}, '
      '${selfie.status.name})';
}
