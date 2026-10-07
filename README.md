# Strip Analyzer

On-device reader for competitive lateral-flow test strips. A YOLO model finds
the test and control lines in a phone photo; the app measures their intensity
and reports POSITIVE / NEGATIVE / INVALID from the T/C ratio.

## Layout

```
flutter_application_1/        Flutter app (iOS + Android)
  lib/
    main.dart                 entry point
    screens/                  strip_analyzer_screen.dart: guided steps, camera, results
    services/
      yolo_detector.dart      runs the native YOLO model
      capture_processing.dart rotate upright + crop the photo to the guide box
      strip_analyzer.dart     line measurement and the positive/negative call
    widgets/                  instruction animations, intensity graph
  assets/
    models/best_int8.tflite   Android model
    html/                     offline instruction animations
    images/                   instruction images
  ios/Runner/best.mlpackage   iOS model
  test/                       unit + widget tests
prototypes/python/            original Python prototype (not used by the app)
```

## Models

Both platforms must run weights from the **same training run**, or the same
strip can read differently on iPhone and Android. The current models come
from `best.pt` (Roboflow dataset, trained Jul 22 2026), with classes
`Back of strip`, `Band`, `Front of strip`:

| Platform | File | Export |
|---|---|---|
| iOS | `ios/Runner/best.mlpackage` | `yolo export model=best.pt format=coreml` |
| Android | `assets/models/best_int8.tflite` | `yolo export model=best.pt format=tflite int8=True` |

After retraining, export **both** from the new `best.pt` and replace both files.
Keep `best.pt` itself somewhere backed up (it is not in this repo).

## Analysis

`StripAnalyzer.analyzeStrip` (in `lib/services/strip_analyzer.dart`):

1. Merges duplicate YOLO boxes on the same line.
2. Uses the `Front of strip` / `Back of strip` detections to tell which line is
   the test line (nearer the front / sample pad). Default: sample pad on the left.
3. For each line, averages the green channel down each column, draws a straight
   baseline through the membrane on either side (cancels uneven lighting), and
   takes the peak relative absorbance inside the box.
4. A line counts as present only if it exceeds 3x the background noise.
5. Thresholds live in `AssayConfig`. **They are not yet calibrated**; set them
   from strips run with known samples.

## Development

```bash
cd flutter_application_1
flutter pub get
flutter test        # unit tests use synthetic strip images
flutter analyze
flutter run
```

In debug builds, the app shows YOLO's annotated boxes after each capture.
