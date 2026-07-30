import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'package:image/image.dart' as img_lib;
import 'strip_analyzer.dart';


class YoloDetector {
 YOLO? _yolo;
 bool _isLoaded = false;


 bool get isLoaded => _isLoaded;


 Future<void> init() async {
   if (_isLoaded) return;
   try {
     _yolo = YOLO(
       modelPath: 'best', // Loads best.mlpackage inside Xcode bundle
       task: YOLOTask.detect,
     );
     await _yolo!.loadModel();
     _isLoaded = true;
     print("DEBUG YOLO: Successfully loaded CoreML model!");
   } catch (e) {
     print("Error loading YOLO model: $e");
   }
 }


 Future<List<YoloPrediction>> detect(File imageFile) async {
   if (!_isLoaded || _yolo == null) {
     print("DEBUG YOLO: Model wasn't ready. Auto-initializing...");
     await init();
   }


   if (!_isLoaded || _yolo == null) {
     print("DEBUG YOLO: Model failed to load during init!");
     return [];
   }
// 1. Read raw image bytes
   final Uint8List originalBytes = await imageFile.readAsBytes();


   // =========================================================================
   // ⚡ IMMEDIATE SOFTWARE FIX: PREPROCESS CONTRAST TO BOOST FAINT LINES
   // =========================================================================
   Uint8List bytesToPredict = originalBytes;


   try {
     final img_lib.Image? decoded = img_lib.decodeImage(originalBytes);
     if (decoded != null) {
       // Fix camera rotation first if needed
       final img_lib.Image oriented = img_lib.bakeOrientation(decoded);


       // Boost contrast (1.3 = +30% contrast) and adjust gamma (0.8 darkens faint bands)
       final img_lib.Image enhanced = img_lib.adjustColor(
         oriented,
         contrast: 1.5,
         gamma: 0.7,
       );


       // Re-encode to high-quality JPEG bytes
       bytesToPredict = Uint8List.fromList(img_lib.encodeJpg(enhanced, quality: 95));
       print("DEBUG YOLO: Successfully boosted contrast for faint line detection.");
     }
   } catch (e) {
     print("DEBUG YOLO: Preprocessing failed, falling back to original image: $e");
   }
   // Pass the raw image bytes directly to native YOLO.
   // The native C++/Core ML layer performs orientation and letterboxing on GPU.
   final imageBytes = await imageFile.readAsBytes();


   final Map<String, dynamic> predictionResult = await _yolo!.predict(
     imageBytes,
     confidenceThreshold: 0.15,
     iouThreshold: 0.25,
   );
// 2. Extract and save the annotated debug image returned directly by YOLO
if (predictionResult.containsKey('annotatedImage') && predictionResult['annotatedImage'] != null) {
 try {
   final List<int> annotatedBytes = List<int>.from(predictionResult['annotatedImage']);
   final tempDir = await getTemporaryDirectory();
   final debugFile = File('${tempDir.path}/yolo_annotated_output.jpg');
   await debugFile.writeAsBytes(annotatedBytes);


   // ⚡ Force Flutter to clear the cached memory for this file path
   await FileImage(debugFile).evict();


   print("=================================================");
   print("🎨 YOLO ANNOTATED IMAGE SAVED AT: ${debugFile.path}");
   print("=================================================");
 } catch (e) {
   print("Failed to save annotated image: $e");
 }
}
   final List<dynamic> results = (predictionResult['boxes'] as List<dynamic>?) ?? [];
   List<YoloPrediction> predictions = [];


   for (var res in results) {
     final Map<String, dynamic> detection = Map<String, dynamic>.from(res);


     final String rawLabel = (detection['className'] ??
             detection['tag'] ??
             detection['label'] ??
             '')
         .toString();
     final double confidence =
         (detection['confidence'] as num?)?.toDouble() ?? 0.0;


     String label = rawLabel.toLowerCase().trim();
     String normalizedClass = label;
     if (label.contains('band') || label.contains('line')) normalizedClass = 'Band';
     if (label.contains('front')) normalizedClass = 'Front of strip';
     if (label.contains('back')) normalizedClass = 'Back of strip';


     final box = detection['box'] ??
         [
           detection['x1'],
           detection['y1'],
           detection['x2'],
           detection['y2']
         ];


     double x1 = (box[0] as num).toDouble();
     double y1 = (box[1] as num).toDouble();
     double x2 = (box[2] as num).toDouble();
     double y2 = (box[3] as num).toDouble();


     double width = (x2 - x1).abs();
     double height = (y2 - y1).abs();
     double centerX = x1 + (width / 2);
     double centerY = y1 + (height / 2);


     predictions.add(YoloPrediction(
       x: centerX,
       y: centerY,
       width: width,
       height: height,
       className: normalizedClass,
       confidence: confidence,
     ));
   }


   return predictions;
 }


 Future<void> dispose() async {
   _isLoaded = false;
 }
}
