import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Captures a painted `RepaintBoundary` as PNG bytes.
///
/// An interface so the save flow can be tested without real raster work; the
/// real implementation is exercised by its own test and by an actual build.
abstract interface class ReceiptPngExporter {
  Future<Uint8List> capture(GlobalKey boundaryKey);
}

class RepaintBoundaryPngExporter implements ReceiptPngExporter {
  const RepaintBoundaryPngExporter();

  @override
  Future<Uint8List> capture(GlobalKey boundaryKey) async {
    final RenderObject? renderObject = boundaryKey.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary || renderObject.size.width <= 0) {
      throw StateError('The receipt is not painted yet.');
    }

    // Phones are narrower than the target image. Cap the ratio so a tablet or a
    // large web viewport cannot allocate an enormous bitmap.
    final double pixelRatio = (1080 / renderObject.size.width)
        .clamp(1.0, 4.0)
        .toDouble();
    final ui.Image image = await renderObject.toImage(pixelRatio: pixelRatio);

    try {
      final ByteData? data = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (data == null) {
        throw StateError('The receipt image could not be encoded.');
      }
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}
