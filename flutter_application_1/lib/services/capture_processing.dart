import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'strip_analyzer.dart';

/// Width of the region analyzed, as a fraction of the photo (matches the
/// on-screen green guide box).
const double guideWidthFraction = 0.95;

/// Width:height of the region analyzed, centered on the guide box.
///
/// Deliberately taller than the green box. The model was trained on ordinary
/// phone photos and loses confidence on thin slivers: on a strip with a faint
/// test line, its confidence in that line was 0.16 with the old 6:1 crop
/// (just above the 0.15 cutoff, and missed on a phone) versus 0.35-0.57 for
/// crops between 5:1 and 2.5:1, and 0.57 at 3:1.
const double cropAspectRatio = 3.0;

/// Turns a raw camera JPEG into the image that is analyzed: rotated upright,
/// cropped around the guide box, and re-encoded without an orientation tag.
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
  final cropHeight = math.min(
    upright.height,
    (cropWidth / cropAspectRatio).round(),
  );
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
