import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'strip_analyzer.dart';

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

/// Decodes a prepared strip JPEG and analyzes it with YOLO's [predictions].
AnalysisResult analyzeStripJpeg((Uint8List, List<YoloPrediction>) job) {
  final (stripJpeg, predictions) = job;
  final image = img.decodeJpg(stripJpeg);
  if (image == null) {
    throw const FormatException('Could not decode the strip image.');
  }
  return StripAnalyzer.analyzeStrip(predictions: predictions, image: image);
}

// Background versions. These pass a top-level function plus its data to
// `compute`, so only that data is copied to the worker isolate. (A closure
// written inside a widget method would carry the method's whole context,
// including unsendable objects like the CameraController.)

Future<Uint8List> prepareCaptureInBackground(Uint8List jpegBytes) =>
    compute(prepareCapture, jpegBytes);

Future<AnalysisResult> analyzeStripJpegInBackground(
  Uint8List stripJpeg,
  List<YoloPrediction> predictions,
) => compute(analyzeStripJpeg, (stripJpeg, predictions));
