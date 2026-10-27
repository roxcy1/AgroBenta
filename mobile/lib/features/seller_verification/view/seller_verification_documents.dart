import 'package:image_picker/image_picker.dart';

import '../../../models/seller_verification.dart';

/// The file extensions `UploadSellerVerificationDocumentRequest` accepts.
///
/// Mirrors the server's `mimes:jpg,jpeg,png,webp`. The server sniffs the actual
/// bytes and remains the authority; this list exists so an obviously wrong pick
/// is stopped on the device with a clear message instead of a `422` round-trip.
const List<String> kVerificationDocumentAllowedExtensions = <String>[
  'jpg',
  'jpeg',
  'png',
  'webp',
];

/// The maximum upload size the server accepts, in bytes (`max:5120` KB).
const int kVerificationDocumentMaxBytes = 5 * 1024 * 1024;

/// Whether [file] is a type the server accepts, judged by its extension.
bool isAllowedVerificationDocument(XFile file) {
  final String name = file.name.toLowerCase();
  final int dot = name.lastIndexOf('.');
  if (dot < 0) {
    return false;
  }
  return kVerificationDocumentAllowedExtensions.contains(name.substring(dot + 1));
}

/// Picks one image for a document card using the platform picker.
///
/// The default picker for production. The form accepts a function of this shape
/// so a test can supply an in-memory file instead of opening a real picker. The
/// source differs per document — a selfie is naturally a camera shot, while an
/// ID is often already saved as an image — but both open the same picker UI and
/// both return a single [XFile].
Future<XFile?> pickVerificationImage(VerificationDocumentType type) async {
  final ImagePicker picker = ImagePicker();
  return picker.pickImage(
    source: type == VerificationDocumentType.selfie
        ? ImageSource.camera
        : ImageSource.gallery,
    maxWidth: 2000,
    maxHeight: 2000,
    imageQuality: 90,
  );
}
