import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// Clean analysis result container without concentration/4PL fields.
class AnalysisResult {
  final double tcRatio;
  final String interpretation;
  final String qualitativeResult; // "POSITIVE", "NEGATIVE", "INVALID"
  final Map<String, dynamic> profileGraph;

  AnalysisResult({
    required this.tcRatio,
    required this.interpretation,
    required this.qualitativeResult,
    required this.profileGraph,
  });

  Map<String, dynamic> toJson() {
    return {
      'tc_ratio': tcRatio,
      'interpretation': interpretation,
      'qualitative_result': qualitativeResult,
      'profile_graph': profileGraph,
    };
  }
}

/// Standardized YOLO prediction class shared across the app.
class YoloPrediction {
  final double x; // Center x
  final double y; // Center y
  final double width;
  final double height;
  final String className;
  final double confidence;

  YoloPrediction({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.className,
    required this.confidence,
  });
}

class StripAnalyzer {
  /// Computes the ratio between Test and Control line densities.
  static double computeTcRatio(double testDensity, double controlDensity) {
    if (controlDensity <= 0) return 0.0;
    return testDensity / controlDensity;
  }

  /// Calculates Euclidean distance between two prediction centroids.
  static double calculateDistance(YoloPrediction a, YoloPrediction b) {
    return math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
  }

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

  /// 1D Gaussian kernel blur filter to reduce camera noise.
  static List<double> gaussianBlur1D(List<double> signal) {
    if (signal.length < 5) return List.from(signal);
    final List<double> kernel = [0.06136, 0.24477, 0.38774, 0.24477, 0.06136];
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

  /// Linear interpolation for profile graph resampling.
  static List<double> interpolate1D(List<double> values, int targetPoints) {
    if (values.isEmpty) return List.filled(targetPoints, 0.0);
    if (values.length == 1) return List.filled(targetPoints, values[0]);
    if (values.length == targetPoints) return List.from(values);

    final List<double> resampled = List.filled(targetPoints, 0.0);
    final double step = (values.length - 1) / (targetPoints - 1);

    for (int i = 0; i < targetPoints; i++) {
      double virtualIdx = i * step;
      int lowIdx = virtualIdx.floor();
      int highIdx = virtualIdx.ceil();
      double fraction = virtualIdx - lowIdx;

      if (highIdx >= values.length) {
        resampled[i] = values.last;
      } else {
        resampled[i] =
            values[lowIdx] * (1.0 - fraction) + values[highIdx] * fraction;
      }
    }
    return resampled;
  }

  /// Advanced signal extraction: Green channel optical absorption,
  /// outer-edge background estimation, Gaussian filtering, and windowed peak integration.
  static Map<String, dynamic> calculateHighPrecisionPeak(
    YoloPrediction box,
    img.Image originalImage,
  ) {
    final int imgWidth = originalImage.width;
    final int imgHeight = originalImage.height;
    final int bx = box.x.toInt();
    final int by = box.y.toInt();
    final int bw = box.width.toInt();
    final int bh = box.height.toInt();

    // Expanded padding to capture surrounding background membrane
    final int padding = (bw * 0.25).round().clamp(10, math.max(10, bw));
    final int x1 = (bx - (bw ~/ 2) - padding).clamp(0, imgWidth - 1);
    final int x2 = (bx + (bw ~/ 2) + padding).clamp(0, imgWidth - 1);
    final int y1 = (by - (bh ~/ 2)).clamp(0, imgHeight - 1);
    final int y2 = (by + (bh ~/ 2)).clamp(0, imgHeight - 1);

    final int roiWidth = x2 - x1;
    final int roiHeight = y2 - y1;

    if (roiWidth <= 0 || roiHeight <= 0) {
      return {"peak": 0.0, "profile": <double>[0.0]};
    }

    // 1. Column-wise integration of the Green channel (maximum absorption contrast)
    final List<double> profileLine = List.filled(roiWidth, 0.0);
    for (int x = 0; x < roiWidth; x++) {
      double colSum = 0.0;
      for (int y = 0; y < roiHeight; y++) {
        final pixel = originalImage.getPixel(x1 + x, y1 + y);
        colSum += pixel.g;
      }
      profileLine[x] = colSum / roiHeight;
    }

    // 2. Dynamic outer-edge baseline background calculation
    final int sampleWidth = (profileLine.length / 6).round().clamp(2, profileLine.length);
    double localBackground = 0.0;
    if (profileLine.length > 2 * sampleWidth) {
      double bgLeft = calculateMedian(profileLine.sublist(0, sampleWidth));
      double bgRight = calculateMedian(profileLine.sublist(profileLine.length - sampleWidth));
      localBackground = (bgLeft + bgRight) / 2.0;
    } else {
      localBackground = calculateMedian(profileLine);
    }

    // 3. Compute relative optical absorption
    List<double> signalProfile = List.filled(profileLine.length, 0.0);
    for (int i = 0; i < profileLine.length; i++) {
      double val = localBackground - profileLine[i];
      signalProfile[i] = val < 0 ? 0.0 : val;
      if (localBackground > 0) {
        signalProfile[i] /= localBackground;
      } else {
        signalProfile[i] = 0.0;
      }
    }

    // 4. Smooth signal noise using 1D Gaussian filter
    if (signalProfile.length >= 5) {
      signalProfile = gaussianBlur1D(signalProfile);
    }

    // 5. Locate max index and calculate windowed peak average
    double maxVal = -1.0;
    int peakIdx = 0;
    for (int i = 0; i < signalProfile.length; i++) {
      if (signalProfile[i] > maxVal) {
        maxVal = signalProfile[i];
        peakIdx = i;
      }
    }

    final int windowRadius = (bw * 0.1).round().clamp(2, math.max(2, bw));
    final int startW = (peakIdx - windowRadius).clamp(0, signalProfile.length - 1);
    final int endW = (peakIdx + windowRadius + 1).clamp(0, signalProfile.length);

    double sum = 0.0;
    int count = 0;
    for (int i = startW; i < endW; i++) {
      sum += signalProfile[i];
      count++;
    }

    double peakValue = count > 0 ? sum / count : 0.0;
    return {"peak": peakValue, "profile": signalProfile};
  }

  /// Constructs standard graph payload for UI rendering.
  static Map<String, dynamic> buildProfileGraphPayload({
    required List<double> testProfile,
    required List<double> controlProfile,
    double? testPeakValue,
    double? controlPeakValue,
    double? tcRatio,
    int points = 12,
  }) {
    List<double> testArr = List.from(testProfile);
    List<double> controlArr = List.from(controlProfile);
    if (testArr.isEmpty) testArr = [0.0];
    if (controlArr.isEmpty) controlArr = [0.0];

    List<double> resampleProfile(List<double> vals) {
      final clipped = vals.map((v) => v < 0.0 ? 0.0 : v).toList();
      return interpolate1D(clipped, points);
    }

    final List<double> testResampled = resampleProfile(testArr);
    final List<double> controlResampled = resampleProfile(controlArr);

    double maxTest = testResampled.reduce(math.max);
    double maxControl = controlResampled.reduce(math.max);
    double sharedMax = math.max(maxTest, maxControl);
    if (sharedMax <= 0) sharedMax = 1.0;

    final List<double> testNorm =
        testResampled.map((v) => v / sharedMax).toList();
    final List<double> controlNorm =
        controlResampled.map((v) => v / sharedMax).toList();

    double rawTestPeak = math.max(0.0, testPeakValue ?? maxTest);
    double rawControlPeak = math.max(0.0, controlPeakValue ?? maxControl);

    return {
      "test_profile": testNorm,
      "control_profile": controlNorm,
      "test_peak_height": testNorm.reduce(math.max),
      "control_peak_height": controlNorm.reduce(math.max),
      "test_line_density": rawTestPeak,
      "control_line_density": rawControlPeak,
      "test_to_control_ratio": tcRatio ?? 0.0,
      "peak_label": "T/C Ratio",
    };
  }

  /// Main analysis entry point.
  static AnalysisResult analyzeStrip({
    required List<YoloPrediction> predictions,
    required img.Image originalImage, 
  }) {
    final List<YoloPrediction> rawBands =
        predictions.where((p) => p.className == "Band").toList();

    // CASE 1: NO BANDS DETECTED
    if (rawBands.isEmpty) {
      return AnalysisResult(
        tcRatio: 0.0,
        interpretation: "No test or control lines detected. Invalid test.",
        qualitativeResult: "INVALID",
        profileGraph: buildProfileGraphPayload(
          testProfile: [],
          controlProfile: [],
        ),
      );
    }

    // CASE 2: SINGLE BAND DETECTED (Control Line Only = Positive in Competitive Assay)
    if (rawBands.length == 1) {
      final peakData = calculateHighPrecisionPeak(rawBands.first, originalImage);
      double cDensity = peakData["peak"];

      if (cDensity <= 0.05) {
        return AnalysisResult(
          tcRatio: 0.0,
          interpretation: "Control line registered as too faint or invalid.",
          qualitativeResult: "INVALID",
          profileGraph: buildProfileGraphPayload(
            testProfile: [],
            controlProfile: [],
          ),
        );
      }

      return AnalysisResult(
        tcRatio: 0.0,
        interpretation:
            "Positive result. Only Control Line present (Test line absent).",
        qualitativeResult: "POSITIVE",
        profileGraph: buildProfileGraphPayload(
          testProfile: [0.0],
          controlProfile: peakData["profile"],
          controlPeakValue: cDensity,
          tcRatio: 0.0,
        ),
      );
    }

    // CASE 3: TWO OR MORE BANDS DETECTED
    final sortedBands = List<YoloPrediction>.from(rawBands)
      ..sort((a, b) => a.x.compareTo(b.x));

    YoloPrediction testBand;
    YoloPrediction controlBand;

    final frontOfStrip = predictions.where(
        (p) => p.className == "Front of strip" || p.className == "front_of_strip");
    final backOfStrip = predictions.where(
        (p) => p.className == "Back of strip" || p.className == "back_of_strip");

    double? frontX = frontOfStrip.isNotEmpty ? frontOfStrip.first.x : null;
    double? backX = backOfStrip.isNotEmpty ? backOfStrip.first.x : null;

    if (frontX != null && backX != null && frontX > backX) {
      testBand = sortedBands[1];
      controlBand = sortedBands[0];
    } else {
      testBand = sortedBands[0];
      controlBand = sortedBands[1];
    }

    final testPeakData = calculateHighPrecisionPeak(testBand, originalImage);
    final controlPeakData = calculateHighPrecisionPeak(controlBand, originalImage);

    double tDensity = testPeakData["peak"];
    double cDensity = controlPeakData["peak"];

    if (cDensity <= 0.05) {
      return AnalysisResult(
        tcRatio: 0.0,
        interpretation: "Control line density registered as unreadable or too faint.",
        qualitativeResult: "INVALID",
        profileGraph: buildProfileGraphPayload(
          testProfile: [],
          controlProfile: [],
        ),
      );
    }

    double computedTcRatio = computeTcRatio(tDensity, cDensity);
    String qualStatus = "NEGATIVE";
    String interpretation = "Negative result. Both Control and Test lines detected.";

    if (computedTcRatio <= 0.02) {
      qualStatus = "POSITIVE";
      interpretation = "Positive result. Test line intensity negligible.";
    }

    return AnalysisResult(
      tcRatio: double.parse(computedTcRatio.toStringAsFixed(4)),
      interpretation: interpretation,
      qualitativeResult: qualStatus,
      profileGraph: buildProfileGraphPayload(
        testProfile: testPeakData["profile"],
        controlProfile: controlPeakData["profile"],
        testPeakValue: tDensity,
        controlPeakValue: cDensity,
        tcRatio: computedTcRatio,
      ),
    );
  }
}