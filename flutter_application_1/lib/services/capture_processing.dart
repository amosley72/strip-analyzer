import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Size of the on-screen green guide box, as a fraction of the photo.
const double guideWidthFraction = 0.95;
const double guideHeightFraction = 0.12;

/// Turns a raw camera JPEG into the image that is analyzed: rotated upright,
/// cropped to the guide box, and re-encoded without an orientation tag.
///
/// Baking the rotation into the pixels matters because the readers disagree
/// on EXIF orientation: iOS's UIImage applies it, Android's BitmapFactory and
/// the Dart `image` package ignore it. Without this, YOLO's boxes and the
/// pixels measured in Dart could be rotated relative to each other.
///
/// Pure function, so it can run in a background isolate.
Uint8List prepareCapture(Uint8List jpegBytes) {
  final decoded = img.decodeImage(jpegBytes);
  if (decoded == null) {
    throw const FormatException('Could not decode the captured photo.');
  }
  final upright = img.bakeOrientation(decoded);

  final cropWidth = (upright.width * guideWidthFraction).round();
  final cropHeight = (upright.height * guideHeightFraction).round();
  final cropped = img.copyCrop(
    upright,
    x: (upright.width - cropWidth) ~/ 2,
    y: (upright.height - cropHeight) ~/ 2,
    width: cropWidth,
    height: cropHeight,
  );
  // High quality: JPEG artifacts at lower settings blur faint lines.
  return img.encodeJpg(cropped, quality: 97);
}
