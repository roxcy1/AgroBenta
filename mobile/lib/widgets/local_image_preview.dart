import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Renders a locally-picked image from its bytes, on every platform.
///
/// `Image.file` reads through `dart:io`, so it is unavailable in a Flutter web
/// build. `XFile.readAsBytes()` is part of `cross_file` and works on both the
/// native and web implementations, which is why this widget exists: the seller
/// listing composer and the verification document card both preview a file the
/// seller has chosen, and both need the same cross-platform behaviour.
///
/// The bytes future is created once per [file] instance and kept in this
/// widget's state. `FutureBuilder` must not be handed a freshly-created future on
/// every build, or a parent rebuild would re-read the file and flash the preview
/// back to its loading state.
class LocalImagePreview extends StatefulWidget {
  const LocalImagePreview({
    required this.file,
    required this.fallback,
    this.fit = BoxFit.cover,
    super.key,
  });

  /// The picked file to show.
  final XFile file;

  /// Shown while no bytes can be read, and whenever decoding fails.
  final Widget fallback;

  /// How the image fills the space its parent gives it.
  final BoxFit fit;

  @override
  State<LocalImagePreview> createState() => _LocalImagePreviewState();
}

class _LocalImagePreviewState extends State<LocalImagePreview> {
  Future<Uint8List>? _bytes;

  /// The instance the cached future belongs to.
  ///
  /// Compared by identity rather than by `path`: an `XFile.fromData` has an
  /// empty path and a generated name, so path equality cannot distinguish two
  /// different picks.
  XFile? _cachedFor;

  @override
  void initState() {
    super.initState();
    _cache(widget.file);
  }

  @override
  void didUpdateWidget(covariant LocalImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.file, _cachedFor)) {
      _cache(widget.file);
    }
  }

  void _cache(XFile file) {
    _cachedFor = file;
    _bytes = file.readAsBytes();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (BuildContext context, AsyncSnapshot<Uint8List> snapshot) {
        final Uint8List? bytes = snapshot.data;
        if (snapshot.hasError) {
          return widget.fallback;
        }
        if (bytes == null) {
          return const Center(
            child: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return Image.memory(
          bytes,
          fit: widget.fit,
          errorBuilder: (BuildContext context, Object error, StackTrace? _) =>
              widget.fallback,
          excludeFromSemantics: true,
        );
      },
    );
  }
}
