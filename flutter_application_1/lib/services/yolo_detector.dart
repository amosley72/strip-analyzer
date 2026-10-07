import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'strip_analyzer.dart';

class Detections {
  final List<YoloPrediction> predictions;

  /// Image with boxes drawn by the native layer, for debugging.
  final Uint8List? annotatedImage;

  const Detections(this.predictions, this.annotatedImage);
}

/// Wraps the native YOLO model. Both platforms run weights exported from the
/// same training run (best.pt): Core ML `best.mlpackage` on iOS and
/// `best_int8.tflite` on Android.
class YoloDetector {
  static const _androidModel = 'assets/models/best_int8.tflite';
  static const _iosModel = 'best'; // ios/Runner/best.mlpackage

  YOLO? _yolo;
  Future<void>? _loading;

  /// Loads the model once; safe to call repeatedly (e.g. to warm up early).
  Future<void> init() => _loading ??= _load();

  Future<void> _load() async {
    final modelPath = Platform.isAndroid ? _androidModel : _iosModel;
    try {
      final yolo = YOLO(modelPath: modelPath, task: YOLOTask.detect);
      if (!await yolo.loadModel()) {
        throw StateError('YOLO model failed to load: $modelPath');
      }
      _yolo = yolo;
      debugPrint('YOLO: loaded $modelPath');
    } catch (_) {
      _loading = null; // allow a retry on the next call
      rethrow;
    }
  }

  /// Runs detection on an upright JPEG. The image is passed as captured, with
  /// no contrast enhancement, because the model was trained on ordinary phone
  /// photos; intensities are measured separately on the same unmodified image.
  Future<Detections> detect(Uint8List imageBytes) async {
    await init();

    final result = await _yolo!.predict(
      imageBytes,
      confidenceThreshold: 0.15,
      iouThreshold: 0.25,
    );

    final raw = (result['boxes'] as List<dynamic>?) ?? const [];
    final size = result['imageSize'] as Map<dynamic, dynamic>?;
    final double imageWidth = (size?['width'] as num?)?.toDouble() ?? 0;
    final double imageHeight = (size?['height'] as num?)?.toDouble() ?? 0;

    final predictions = <YoloPrediction>[];
    for (final item in raw) {
      final detection = Map<String, dynamic>.from(item as Map);

      double coord(String key, double scale) {
        final norm = detection['${key}_norm'] as num?;
        if (norm != null) return norm.toDouble();
        final px = (detection[key] as num?)?.toDouble() ?? 0;
        return scale > 0 ? px / scale : px;
      }

      final x1 = coord('x1', imageWidth);
      final y1 = coord('y1', imageHeight);
      final x2 = coord('x2', imageWidth);
      final y2 = coord('y2', imageHeight);

      predictions.add(
        YoloPrediction(
          x: (x1 + x2) / 2,
          y: (y1 + y2) / 2,
          width: (x2 - x1).abs(),
          height: (y2 - y1).abs(),
          className: _normalizeClass(
            (detection['className'] ?? detection['class'] ?? '').toString(),
          ),
          confidence: (detection['confidence'] as num?)?.toDouble() ?? 0.0,
        ),
      );
    }

    final annotated = result['annotatedImage'];
    return Detections(
      predictions,
      annotated == null ? null : Uint8List.fromList(List<int>.from(annotated)),
    );
  }

  static String _normalizeClass(String raw) {
    final label = raw.toLowerCase().trim();
    if (label.contains('front')) return YoloClass.front;
    if (label.contains('back')) return YoloClass.back;
    if (label.contains('band') || label.contains('line')) return YoloClass.band;
    return raw;
  }

  Future<void> dispose() async {
    await _yolo?.dispose();
    _yolo = null;
    _loading = null;
  }
}
