import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'attachment_types.dart';

/// Result of decoding and normalising an image in a worker isolate.
class ProcessedImage {
  const ProcessedImage({
    this.bytes,
    this.thumbnail,
    this.width,
    this.height,
    this.error,
  });

  final Uint8List? bytes;
  final Uint8List? thumbnail;
  final int? width;
  final int? height;
  final String? error;

  bool get isSuccess => error == null && bytes != null;
}

/// Decodes, orients, downscales and re-encodes an image off the UI isolate.
///
/// Re-encoding strips EXIF (including GPS) by construction. With
/// [keepOriginal] the original bytes are stored instead, but the thumbnail is
/// still regenerated and the pixel limit still applies.
Future<ProcessedImage> processImageBytes(
  Uint8List original, {
  required bool keepOriginal,
}) {
  return Isolate.run(() => _process(original, keepOriginal));
}

ProcessedImage _process(Uint8List original, bool keepOriginal) {
  final decoded = img.decodeImage(original);
  if (decoded == null) {
    return const ProcessedImage(error: 'This file is not a readable image.');
  }
  if (decoded.width * decoded.height > AttachmentRules.maxImagePixels) {
    return const ProcessedImage(
      error: 'This image is too large to process safely.',
    );
  }

  final oriented = img.bakeOrientation(decoded);
  final thumb = _resizeLongEdge(oriented, AttachmentRules.thumbnailEdge);
  final thumbBytes = _encode(thumb, AttachmentRules.thumbnailQuality);

  if (keepOriginal) {
    return ProcessedImage(
      bytes: original,
      thumbnail: thumbBytes,
      width: oriented.width,
      height: oriented.height,
    );
  }

  final resized = _resizeLongEdge(oriented, AttachmentRules.maxLongEdge);
  return ProcessedImage(
    bytes: _encode(resized, AttachmentRules.jpegQuality),
    thumbnail: thumbBytes,
    width: resized.width,
    height: resized.height,
  );
}

img.Image _resizeLongEdge(img.Image source, int maxEdge) {
  final longest = max(source.width, source.height);
  if (longest <= maxEdge) return source;
  if (source.width >= source.height) {
    return img.copyResize(
      source,
      width: maxEdge,
      interpolation: img.Interpolation.average,
    );
  }
  return img.copyResize(
    source,
    height: maxEdge,
    interpolation: img.Interpolation.average,
  );
}

Uint8List _encode(img.Image image, int quality) {
  // Preserve transparency as PNG; everything else becomes a compact JPEG with
  // no metadata.
  if (image.hasAlpha) return Uint8List.fromList(img.encodePng(image));
  return Uint8List.fromList(img.encodeJpg(image, quality: quality));
}
