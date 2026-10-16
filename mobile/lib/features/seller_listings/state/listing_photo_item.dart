import 'package:image_picker/image_picker.dart';

/// The lifecycle of one photo in the listing photo composer.
enum ListingPhotoStatus {
  /// Picked locally, not yet sent to the server.
  pending,

  /// Included in an upload request in flight.
  uploading,

  /// Stored on the server; [ListingPhotoItem.url] is the absolute URL to render.
  uploaded,

  /// The upload request failed; retryable.
  failed,
}

/// One photo the seller is composing for a listing: either a locally-picked
/// file waiting to be uploaded, or a photo the server has already stored and
/// served as an absolute URL.
///
/// The position in the list is the display order. New picks append at the end;
/// uploads append to the stored set server-side in the same order; deletion
/// removes by the served value (never by index, so a reorder can never point
/// at the wrong file).
class ListingPhotoItem {
  const ListingPhotoItem({
    required this.id,
    required this.status,
    this.file,
    this.url,
    this.progress,
    this.error,
  });

  static int _nextId = 0;

  /// Wraps freshly-picked files as new, not-yet-uploaded items, in pick order.
  static List<ListingPhotoItem> fromPicked(List<XFile> picked) {
    return picked
        .map(
          (XFile file) => ListingPhotoItem(
            id: 'photo_${_nextId++}',
            status: ListingPhotoStatus.pending,
            file: file,
          ),
        )
        .toList(growable: false);
  }

  /// An item the server has already stored, keyed by the absolute URL it served.
  factory ListingPhotoItem.uploaded(String url) {
    return ListingPhotoItem(
      id: url,
      status: ListingPhotoStatus.uploaded,
      url: url,
    );
  }

  /// Stable client-side id. For uploaded items this is the served URL; for new
  /// items it is a generated id.
  final String id;

  final ListingPhotoStatus status;

  /// The locally-picked file, present while the photo is not yet stored.
  final XFile? file;

  /// The absolute URL the server served, present once stored.
  final String? url;

  /// Upload progress from 0.0 to 1.0 while [status] is [uploading].
  final double? progress;

  /// Failure message while [status] is [failed].
  final String? error;

  /// Whether the photo exists only locally and has nothing to delete on the
  /// server.
  bool get isLocalOnly => status == ListingPhotoStatus.pending && url == null;

  /// The value to name in a delete request: the served URL once stored.
  ///
  /// A locally-picked photo that was never uploaded has no server counterpart,
  /// so deleting it is a local-only operation.
  String? get deleteValue => url;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ListingPhotoItem &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  ListingPhotoItem copyWith({
    ListingPhotoStatus? status,
    XFile? file,
    String? url,
    double? progress,
    String? error,
  }) {
    return ListingPhotoItem(
      id: id,
      status: status ?? this.status,
      file: file ?? this.file,
      url: url ?? this.url,
      progress: progress ?? this.progress,
      error: error ?? this.error,
    );
  }

  @override
  String toString() =>
      'ListingPhotoItem($id, ${status.name}, ${file?.name ?? ''}, $url)';
}
