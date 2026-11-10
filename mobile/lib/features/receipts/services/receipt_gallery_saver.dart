import 'dart:typed_data';

import 'package:gal/gal.dart';

/// Why a receipt could not be saved to the gallery.
enum ReceiptGalleryError {
  accessDenied,
  notEnoughSpace,
  notSupportedFormat,
  unexpected,
  unsupported,
}

extension ReceiptGalleryErrorCopy on ReceiptGalleryError {
  String get message => switch (this) {
    ReceiptGalleryError.accessDenied =>
      'Photo library access was denied. Allow it in Settings to save the '
          'receipt.',
    ReceiptGalleryError.notEnoughSpace =>
      'There is not enough space to save the receipt.',
    ReceiptGalleryError.notSupportedFormat =>
      'This device could not save the receipt image.',
    ReceiptGalleryError.unsupported =>
      'Saving to the gallery is available in the Android and iOS app.',
    ReceiptGalleryError.unexpected =>
      'Could not save the receipt. Please try again.',
  };
}

class ReceiptGalleryException implements Exception {
  const ReceiptGalleryException(this.error);

  final ReceiptGalleryError error;

  String get message => error.message;

  @override
  String toString() => 'ReceiptGalleryException(${error.name})';
}

/// Saves receipt PNG bytes to the device photo library.
///
/// An interface so widget tests can use a fake and never touch a platform
/// channel.
abstract interface class ReceiptGallerySaver {
  Future<void> save(Uint8List pngBytes, {required String name});
}

/// The real saver, backed by `gal`.
///
/// Access is requested only when the user taps Save, never on screen open. The
/// caller must not pass a file extension: gal derives it from the image bytes.
class GalReceiptGallerySaver implements ReceiptGallerySaver {
  const GalReceiptGallerySaver();

  @override
  Future<void> save(Uint8List pngBytes, {required String name}) async {
    try {
      if (!await Gal.hasAccess()) {
        await Gal.requestAccess();
        if (!await Gal.hasAccess()) {
          throw const ReceiptGalleryException(
            ReceiptGalleryError.accessDenied,
          );
        }
      }

      await Gal.putImageBytes(pngBytes, name: name);
    } on ReceiptGalleryException {
      rethrow;
    } on GalException catch (error) {
      throw ReceiptGalleryException(_map(error.type));
    } on Object {
      throw const ReceiptGalleryException(ReceiptGalleryError.unexpected);
    }
  }

  static ReceiptGalleryError _map(GalExceptionType type) => switch (type) {
    GalExceptionType.accessDenied => ReceiptGalleryError.accessDenied,
    GalExceptionType.notEnoughSpace => ReceiptGalleryError.notEnoughSpace,
    GalExceptionType.notSupportedFormat =>
      ReceiptGalleryError.notSupportedFormat,
    GalExceptionType.unexpected => ReceiptGalleryError.unexpected,
  };
}
