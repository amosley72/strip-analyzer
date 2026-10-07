import 'dart:math' as math;
import 'package:afts_reader/services/capture_processing.dart';
import 'package:afts_reader/services/strip_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const int kWidth = 600;
const int kHeight = 60;
const double kMembrane = 200; // green-channel value of blank membrane
const int kLineWidth = 12;

/// A synthetic strip photo: uniform membrane with camera-like noise, plus
/// vertical lines at [lines] (x center -> darkness, 0 = invisible, 1 = black).
/// [gradient] darkens the image linearly from left (0) to right (gradient),
/// like a shadow or uneven lighting.
img.Image stripImage(
  Map<int, double> lines, {
  double noise = 3,
  int seed = 1,
  double gradient = 0,
}) {
  final random = math.Random(seed);
  final image = img.Image(width: kWidth, height: kHeight);
  for (int x = 0; x < kWidth; x++) {
    double level = kMembrane * (1 - gradient * x / kWidth);
    lines.forEach((center, darkness) {
      if ((x - center).abs() <= kLineWidth ~/ 2) {
        level *= 1 - darkness;
      }
    });
    for (int y = 0; y < kHeight; y++) {
      // Sum of uniforms approximates Gaussian noise.
      final n =
          (random.nextDouble() +
              random.nextDouble() +
              random.nextDouble() -
              1.5) *
          2 *
          noise;
      final v = (level + n).clamp(0, 255).round();
      image.setPixelRgb(x, y, v, v, v);
    }
  }
  return image;
}

/// A YOLO box around a line centered at pixel [centerX].
YoloPrediction box(
  int centerX, {
  String cls = YoloClass.band,
  double confidence = 0.9,
  int width = 30,
}) {
  return YoloPrediction(
    x: centerX / kWidth,
    y: 0.5,
    width: width / kWidth,
    height: 0.8,
    className: cls,
    confidence: confidence,
  );
}

void main() {
  group('analyzeStrip', () {
    test('no bands is invalid', () {
      final result = StripAnalyzer.analyzeStrip(
        predictions: [],
        image: stripImage({}),
      );
      expect(result.outcome, TestOutcome.invalid);
    });

    test('visible test and control lines is negative with sensible ratio', () {
      final result = StripAnalyzer.analyzeStrip(
        predictions: [box(200), box(400)],
        image: stripImage({200: 0.3, 400: 0.4}),
      );
      expect(result.outcome, TestOutcome.negative);
      expect(result.tcRatio, closeTo(0.75, 0.1));
    });

    test('control line only is positive', () {
      final result = StripAnalyzer.analyzeStrip(
        predictions: [box(400)],
        image: stripImage({400: 0.4}),
      );
      expect(result.outcome, TestOutcome.positive);
    });

    test('a "test band" box on blank membrane is positive, not negative', () {
      // Old behavior: the max of clipped noise gave T/C above 0.02 -> NEGATIVE.
      for (int seed = 1; seed <= 20; seed++) {
        final result = StripAnalyzer.analyzeStrip(
          predictions: [box(200, confidence: 0.2), box(400)],
          image: stripImage({400: 0.4}, noise: 6, seed: seed),
        );
        expect(result.outcome, TestOutcome.positive, reason: 'seed $seed');
      }
    });

    test('uneven lighting over a blank test region is not read as a line', () {
      // A 25% brightness falloff across the strip, no test line.
      for (int seed = 1; seed <= 20; seed++) {
        final result = StripAnalyzer.analyzeStrip(
          predictions: [box(200, confidence: 0.2), box(400)],
          image: stripImage({400: 0.4}, gradient: 0.25, seed: seed),
        );
        expect(result.outcome, TestOutcome.positive, reason: 'seed $seed');
      }
    });

    test(
      'two boxes on the same control line are merged, not read as T and C',
      () {
        // Old behavior: T and C were the same line, ratio ~1 -> NEGATIVE.
        final result = StripAnalyzer.analyzeStrip(
          predictions: [box(400, confidence: 0.9), box(404, confidence: 0.4)],
          image: stripImage({400: 0.4}),
        );
        expect(result.outcome, TestOutcome.positive);
      },
    );

    test('faint control line is invalid', () {
      final result = StripAnalyzer.analyzeStrip(
        predictions: [box(200), box(400)],
        image: stripImage({200: 0.3, 400: 0.02}),
      );
      expect(result.outcome, TestOutcome.invalid);
    });

    test(
      'front of strip on the right makes the right-hand line the test line',
      () {
        final result = StripAnalyzer.analyzeStrip(
          predictions: [
            box(200),
            box(400),
            box(560, cls: YoloClass.front, width: 60),
            box(40, cls: YoloClass.back, width: 60),
          ],
          image: stripImage({200: 0.4, 400: 0.1}),
        );
        expect(result.tcRatio, closeTo(0.25, 0.06));
      },
    );

    test('more than two distinct lines is invalid', () {
      final result = StripAnalyzer.analyzeStrip(
        predictions: [box(150), box(300), box(450)],
        image: stripImage({150: 0.3, 300: 0.3, 450: 0.4}),
      );
      expect(result.outcome, TestOutcome.invalid);
    });
  });

  group('measureLine', () {
    test('signal tracks line darkness', () {
      final line = StripAnalyzer.measureLine(box(300), stripImage({300: 0.25}));
      expect(line.signal, closeTo(0.25, 0.03));
      expect(line.noise, lessThan(0.02));
    });

    test('blank membrane reads below the noise threshold', () {
      final line = StripAnalyzer.measureLine(
        box(300),
        stripImage({}, noise: 6),
      );
      expect(line.signal, lessThan(3 * line.noise + 1e-9));
    });
  });

  test('mergeDuplicateBands keeps the most confident box per line', () {
    final merged = StripAnalyzer.mergeDuplicateBands([
      box(400, confidence: 0.3),
      box(405, confidence: 0.8),
      box(200, confidence: 0.5),
    ]);
    expect(merged.map((b) => b.confidence), unorderedEquals([0.8, 0.5]));
  });

  test('prepareCapture rotates by EXIF orientation before cropping', () {
    final landscape = img.Image(width: 400, height: 300);
    landscape.exif.imageIfd.orientation = 6; // stored rotated 90°
    final prepared = img.decodeJpg(prepareCapture(img.encodeJpg(landscape)))!;
    expect(prepared.width, (300 * guideWidthFraction).round());
    expect(
      prepared.height,
      ((300 * guideWidthFraction).round() / cropAspectRatio).round(),
    );
    expect(prepared.exif.imageIfd.orientation ?? 1, 1);
  });

  group('background isolates (the capture path on a phone)', () {
    test('prepareCaptureInBackground returns a cropped JPEG', () async {
      final photo = img.encodeJpg(img.Image(width: 400, height: 300));
      final prepared = img.decodeJpg(await prepareCaptureInBackground(photo))!;
      expect(prepared.width, (400 * guideWidthFraction).round());
    });

    test(
      'analyzeStripJpegInBackground analyzes YOLO boxes on the JPEG',
      () async {
        final jpeg = img.encodeJpg(
          stripImage({200: 0.3, 400: 0.4}),
          quality: 97,
        );
        final result = await analyzeStripJpegInBackground(jpeg, [
          box(200),
          box(400),
        ]);
        expect(result.outcome, TestOutcome.negative);
        expect(result.tcRatio, closeTo(0.75, 0.12));
      },
    );
  });
}
