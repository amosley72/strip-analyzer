import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// Class names produced by the YOLO model (see `names` in best.pt).
class YoloClass {
  static const band = 'Band';
  static const front = 'Front of strip';
  static const back = 'Back of strip';
}

/// A single YOLO detection. Coordinates are normalized to 0–1 of the image
/// that was analyzed, so they stay valid no matter how the native layer
/// resized the image.
class YoloPrediction {
  final double x; // center x
  final double y; // center y
  final double width;
  final double height;
  final String className;
  final double confidence;

  const YoloPrediction({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.className,
    required this.confidence,
  });

  double get left => x - width / 2;
  double get right => x + width / 2;
}

/// Thresholds for the qualitative call.
///
/// These are starting values, NOT calibrated ones. Re-derive them from strips
/// run with known samples (blanks, and concentrations around the cutoff) and
/// record the sensitivity/specificity they give.
class AssayConfig {
  /// T/C ratio at or below which the test line counts as absent (positive).
  final double positiveCutoffRatio;

  /// Minimum control-line signal (relative absorbance) for a valid strip.
  final double minControlSignal;

  /// A line only counts as present when its signal exceeds this many standard
  /// deviations of the membrane background noise next to it.
  final double noiseSigmas;

  /// Two band boxes overlapping horizontally by more than this fraction (of
  /// the narrower box) are treated as the same physical line.
  final double duplicateOverlap;

  const AssayConfig({
    this.positiveCutoffRatio = 0.02,
    this.minControlSignal = 0.05,
    this.noiseSigmas = 3.0,
    this.duplicateOverlap = 0.3,
  });
}

enum TestOutcome { positive, negative, invalid }

extension TestOutcomeLabel on TestOutcome {
  String get label => name.toUpperCase();
}

/// Signal measured across one detected line.
class LineMeasurement {
  /// Background-normalized absorbance at the line (0 = same as membrane).
  final double signal;

  /// Standard deviation of the background around the line, same units.
  final double noise;

  /// Smoothed absorbance profile across the line, clipped at 0, for graphing.
  final List<double> profile;

  const LineMeasurement({
    required this.signal,
    required this.noise,
    required this.profile,
  });

  static const empty = LineMeasurement(signal: 0, noise: 0, profile: []);
}

class AnalysisResult {
  final TestOutcome outcome;
  final String interpretation;
  final double tcRatio;
  final LineMeasurement test;
  final LineMeasurement control;

  const AnalysisResult({
    required this.outcome,
    required this.interpretation,
    this.tcRatio = 0.0,
    this.test = LineMeasurement.empty,
    this.control = LineMeasurement.empty,
  });

  factory AnalysisResult.invalid(
    String interpretation, {
    LineMeasurement control = LineMeasurement.empty,
  }) => AnalysisResult(
    outcome: TestOutcome.invalid,
    interpretation: interpretation,
    control: control,
  );
}

class StripAnalyzer {
  /// Calculates median of a list of double values.
  static double calculateMedian(List<double> values) {
    if (values.isEmpty) return 0.0;
    final List<double> sorted = List.from(values)..sort();
    int middle = sorted.length ~/ 2;
    if (sorted.length % 2 == 1) {
      return sorted[middle];
    } else {
      return (sorted[middle - 1] + sorted[middle]) / 2.0;
    }
  }

  static double _standardDeviation(List<double> values) {
    if (values.length < 2) return 0.0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
        (values.length - 1);
    return math.sqrt(variance);
  }

  /// 1D Gaussian kernel blur filter to reduce camera noise.
  static List<double> gaussianBlur1D(List<double> signal) {
    if (signal.length < 5) return List.from(signal);
    const List<double> kernel = [0.06136, 0.24477, 0.38774, 0.24477, 0.06136];
    final List<double> blurred = List.filled(signal.length, 0.0);

    for (int i = 0; i < signal.length; i++) {
      double sum = 0.0;
      double weightSum = 0.0;
      for (int k = -2; k <= 2; k++) {
        int idx = i + k;
        if (idx >= 0 && idx < signal.length) {
          sum += signal[idx] * kernel[k + 2];
          weightSum += kernel[k + 2];
        }
      }
      blurred[i] = weightSum > 0 ? sum / weightSum : signal[i];
    }
    return blurred;
  }

  /// Fraction of the narrower box's width that two boxes share horizontally.
  static double horizontalOverlap(YoloPrediction a, YoloPrediction b) {
    final overlap = math.min(a.right, b.right) - math.max(a.left, b.left);
    final narrower = math.min(a.width, b.width);
    if (overlap <= 0 || narrower <= 0) return 0.0;
    return overlap / narrower;
  }

  /// Collapses overlapping band boxes (YOLO sometimes boxes one line twice),
  /// keeping the most confident box for each physical line.
  static List<YoloPrediction> mergeDuplicateBands(
    List<YoloPrediction> bands, {
    double maxOverlap = 0.3,
  }) {
    final byConfidence = List<YoloPrediction>.from(bands)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final kept = <YoloPrediction>[];
    for (final band in byConfidence) {
      if (kept.every((k) => horizontalOverlap(k, band) <= maxOverlap)) {
        kept.add(band);
      }
    }
    return kept;
  }

  /// Whether the front of the strip (sample pad end, where the test line
  /// sits) is on the right side of the image. The instructions put it on the
  /// left, so that is the default when YOLO finds neither end.
  static bool frontIsOnRight(List<YoloPrediction> predictions) {
    YoloPrediction? best(String cls) {
      final matches = predictions.where((p) => p.className == cls).toList()
        ..sort((a, b) => b.confidence.compareTo(a.confidence));
      return matches.isEmpty ? null : matches.first;
    }

    final front = best(YoloClass.front);
    final back = best(YoloClass.back);
    if (front != null && back != null) return front.x > back.x;
    if (front != null) return front.x > 0.5;
    if (back != null) return back.x < 0.5;
    return false;
  }

  /// Measures one line: green-channel absorbance relative to a baseline drawn
  /// through the membrane on either side, smoothed, with the peak searched
  /// only inside the YOLO box.
  static LineMeasurement measureLine(YoloPrediction box, img.Image image) {
    final int imgWidth = image.width;
    final int imgHeight = image.height;
    final int bw = (box.width * imgWidth).round();
    final int bh = (box.height * imgHeight).round();
    final int boxLeft = (box.left * imgWidth).round();
    final int boxRight = (box.right * imgWidth).round();
    final int cy = (box.y * imgHeight).round();

    // Expanded padding to capture surrounding background membrane
    final int padding = math.max(10, (bw * 0.25).round());
    final int x1 = (boxLeft - padding).clamp(0, imgWidth - 1);
    final int x2 = (boxRight + padding).clamp(0, imgWidth - 1);
    final int y1 = (cy - bh ~/ 2).clamp(0, imgHeight - 1);
    final int y2 = (cy + bh ~/ 2).clamp(0, imgHeight - 1);

    final int roiWidth = x2 - x1;
    final int roiHeight = y2 - y1;
    if (roiWidth < 5 || roiHeight <= 0) return LineMeasurement.empty;

    // 1. Column-wise mean of the Green channel (maximum absorption contrast)
    final List<double> profileLine = List.filled(roiWidth, 0.0);
    for (int x = 0; x < roiWidth; x++) {
      double colSum = 0.0;
      for (int y = 0; y < roiHeight; y++) {
        colSum += image.getPixel(x1 + x, y1 + y).g;
      }
      profileLine[x] = colSum / roiHeight;
    }

    // 2. Background from the outer edges of the profile (the membrane)
    final int sampleWidth = (profileLine.length / 6).round().clamp(
      2,
      profileLine.length ~/ 2,
    );
    final List<double> leftEdge = profileLine.sublist(0, sampleWidth);
    final List<double> rightEdge = profileLine.sublist(
      profileLine.length - sampleWidth,
    );
    final double bgLeft = calculateMedian(leftEdge);
    final double bgRight = calculateMedian(rightEdge);
    if (bgLeft <= 0 || bgRight <= 0) return LineMeasurement.empty;

    // 3. Baseline: a straight line between the left and right membrane
    //    levels, so uneven lighting across the box is not read as a line.
    //    Signal is relative absorbance against that baseline (kept signed so
    //    the noise estimate is unbiased), then smoothed.
    final double leftCenter = (sampleWidth - 1) / 2;
    final double rightCenter = profileLine.length - 1 - leftCenter;
    double baseline(int i) =>
        bgLeft +
        (bgRight - bgLeft) * (i - leftCenter) / (rightCenter - leftCenter);
    final List<double> signal = gaussianBlur1D([
      for (int i = 0; i < profileLine.length; i++)
        (baseline(i) - profileLine[i]) / baseline(i),
    ]);

    // 4. Noise: spread of the smoothed signal over the membrane samples.
    final double noise = _standardDeviation([
      ...signal.sublist(0, sampleWidth),
      ...signal.sublist(signal.length - sampleWidth),
    ]);

    // 5. Peak: maximum inside the YOLO box only (not the padding, which could
    //    hold a neighboring line), averaged over a small window.
    final int innerStart = (boxLeft - x1).clamp(0, signal.length - 1);
    final int innerEnd = (boxRight - x1).clamp(innerStart + 1, signal.length);
    int peakIdx = innerStart;
    for (int i = innerStart; i < innerEnd; i++) {
      if (signal[i] > signal[peakIdx]) peakIdx = i;
    }
    final int windowRadius = math.max(2, (bw * 0.1).round());
    final int startW = math.max(0, peakIdx - windowRadius);
    final int endW = math.min(signal.length, peakIdx + windowRadius + 1);
    double sum = 0.0;
    for (int i = startW; i < endW; i++) {
      sum += signal[i];
    }
    final double peak = math.max(0.0, sum / (endW - startW));

    return LineMeasurement(
      signal: peak,
      noise: noise,
      profile: signal.map((v) => v < 0 ? 0.0 : v).toList(),
    );
  }

  /// Main analysis entry point.
  static AnalysisResult analyzeStrip({
    required List<YoloPrediction> predictions,
    required img.Image image,
    AssayConfig config = const AssayConfig(),
  }) {
    final bands = mergeDuplicateBands(
      predictions.where((p) => p.className == YoloClass.band).toList(),
      maxOverlap: config.duplicateOverlap,
    );

    bool isReadable(LineMeasurement line, double minimum) =>
        line.signal > minimum && line.signal > config.noiseSigmas * line.noise;

    // CASE 1: NO BANDS DETECTED
    if (bands.isEmpty) {
      return AnalysisResult.invalid(
        "No test or control lines detected. Invalid test.",
      );
    }

    // More than two distinct lines means something other than T and C was
    // detected (shadow, MAX line, strip edge). Guessing which two are real
    // risks reading the wrong line as the test line, so ask for a retake.
    if (bands.length > 2) {
      return AnalysisResult.invalid(
        "${bands.length} lines detected; expected 2. Retake the photo "
        "with the strip flat, evenly lit, and centered in the box.",
      );
    }

    // CASE 2: SINGLE BAND (Control Line Only = Positive in Competitive Assay)
    if (bands.length == 1) {
      final control = measureLine(bands.first, image);
      if (!isReadable(control, config.minControlSignal)) {
        return AnalysisResult.invalid(
          "Control line registered as too faint or invalid.",
          control: control,
        );
      }
      return AnalysisResult(
        outcome: TestOutcome.positive,
        interpretation:
            "Positive result. Only Control Line present (Test line absent).",
        control: control,
      );
    }

    // CASE 3: TWO BANDS. The test line is the one nearer the front of the
    // strip (sample pad end).
    final byPosition = List<YoloPrediction>.from(bands)
      ..sort((a, b) => a.x.compareTo(b.x));
    final bool frontRight = frontIsOnRight(predictions);
    final testBand = frontRight ? byPosition[1] : byPosition[0];
    final controlBand = frontRight ? byPosition[0] : byPosition[1];

    final test = measureLine(testBand, image);
    final control = measureLine(controlBand, image);

    if (!isReadable(control, config.minControlSignal)) {
      return AnalysisResult.invalid(
        "Control line density registered as unreadable or too faint.",
        control: control,
      );
    }

    final double tcRatio = test.signal / control.signal;
    final bool testPresent = isReadable(test, 0.0);

    if (!testPresent || tcRatio <= config.positiveCutoffRatio) {
      return AnalysisResult(
        outcome: TestOutcome.positive,
        interpretation: testPresent
            ? "Positive result. Test line intensity negligible."
            : "Positive result. Test line indistinguishable from background.",
        tcRatio: tcRatio,
        test: test,
        control: control,
      );
    }

    return AnalysisResult(
      outcome: TestOutcome.negative,
      interpretation: "Negative result. Both Control and Test lines detected.",
      tcRatio: tcRatio,
      test: test,
      control: control,
    );
  }
}
