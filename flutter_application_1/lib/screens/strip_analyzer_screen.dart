import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/capture_processing.dart';
import '../services/strip_analyzer.dart';
import '../services/yolo_detector.dart';
import '../widgets/html_animation.dart';
import '../widgets/profile_graph.dart';

class StripAnalyzerScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  /// Injectable for tests; defaults to the real native model.
  final YoloDetector? detector;

  const StripAnalyzerScreen({super.key, required this.cameras, this.detector});

  @override
  StripAnalyzerScreenState createState() => StripAnalyzerScreenState();
}

class StripAnalyzerScreenState extends State<StripAnalyzerScreen> {
  static const int _waitSeconds = 300;

  late final YoloDetector _detector = widget.detector ?? YoloDetector();
  CameraController? _cameraController;
  bool _isCameraMode = false;
  bool _isAnalyzing = false;
  AnalysisResult? _result;
  bool _showHomeScreen = true;
  int _instructionStep = 1;
  bool _showStepFiveInstructions = false;
  Timer? _countdownTimer;
  int _countdownSeconds = _waitSeconds;
  bool _countdownComplete = false;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _cameraController?.dispose();
    _detector.dispose();
    super.dispose();
  }

  Future<void> _startCamera() async {
    if (widget.cameras.isEmpty) {
      _showSnackBar('No camera available on this device.');
      return;
    }
    // Load the model while the user lines up the strip. Errors resurface
    // (and are reported) when detection runs.
    unawaited(_detector.init().catchError((Object _) {}));

    final backCamera = widget.cameras.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.back,
      orElse: () => widget.cameras.first,
    );
    final controller = CameraController(
      backCamera,
      ResolutionPreset.max,
      enableAudio: false,
    );
    try {
      await controller.initialize();
      await controller.setFocusMode(FocusMode.auto);
      await controller.setZoomLevel(2.0);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _showHomeScreen = false;
        _showStepFiveInstructions = false;
        _isCameraMode = true;
        _instructionStep = 5;
      });
    } catch (e) {
      await controller.dispose();
      _showSnackBar('Camera initialization failed: $e');
    }
  }

  void _stopCamera({bool returnToStep = true}) {
    _countdownTimer?.cancel();
    final controller = _cameraController;
    setState(() {
      _isCameraMode = false;
      _cameraController = null;
      if (returnToStep) {
        _showHomeScreen = false;
        _showStepFiveInstructions = false;
        _instructionStep = 5;
      }
    });
    controller?.dispose();
  }

  Future<void> _performCapture() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized || _isAnalyzing) {
      return;
    }
    setState(() {
      _isAnalyzing = true; // also blocks a second tap while capturing
      _result = null;
    });
    try {
      final photo = await controller.takePicture();
      final rawBytes = await photo.readAsBytes();
      if (!mounted) return;
      _stopCamera(returnToStep: false);

      // Heavy image work runs off the UI thread.
      final stripJpeg = await prepareCaptureInBackground(rawBytes);
      final detections = await _detector.detect(stripJpeg);
      final predictions = detections.predictions;
      final result = await analyzeStripJpegInBackground(stripJpeg, predictions);

      if (!mounted) return;
      setState(() => _result = result);
      if (kDebugMode && detections.annotatedImage != null) {
        _showDebugDetections(detections.annotatedImage!);
      }
    } catch (e) {
      _showSnackBar('Analysis failed: $e');
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  /// Debug builds only: shows YOLO's boxes for the photo just analyzed.
  void _showDebugDetections(Uint8List annotatedImage) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("YOLO Output (With Bounding Boxes)"),
        content: Image.memory(annotatedImage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _beginTestingProcedure() {
    _countdownTimer?.cancel();
    setState(() {
      _showHomeScreen = false;
      _instructionStep = 1;
      _showStepFiveInstructions = false;
      _countdownComplete = false;
      _countdownSeconds = _waitSeconds;
      _isCameraMode = false;
    });
  }

  void _startDirectAnalysis() {
    _countdownTimer?.cancel();
    setState(() {
      _showHomeScreen = false;
      _instructionStep = 5;
      _showStepFiveInstructions = true;
      _isCameraMode = false;
      _countdownComplete = false;
      _countdownSeconds = _waitSeconds;
    });
  }

  void _goToNextStep() {
    if (_instructionStep < 5) {
      setState(() {
        _instructionStep += 1;
        _showStepFiveInstructions = false;
        _countdownComplete = false;
        _countdownSeconds = _waitSeconds;
      });
      if (_instructionStep == 3) {
        _startCountdown();
      } else {
        _countdownTimer?.cancel();
      }
    } else {
      setState(() {
        _showStepFiveInstructions = true;
      });
    }
  }

  void _goToPreviousStep() {
    if (_instructionStep > 1) {
      _countdownTimer?.cancel();
      setState(() {
        _instructionStep -= 1;
        _showStepFiveInstructions = false;
        _countdownComplete = false;
        _countdownSeconds = _waitSeconds;
      });
      if (_instructionStep == 3) {
        _startCountdown();
      }
    } else {
      setState(() {
        _showHomeScreen = true;
        _instructionStep = 1;
        _showStepFiveInstructions = false;
        _isCameraMode = false;
      });
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _countdownSeconds = _waitSeconds;
      _countdownComplete = false;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_countdownSeconds > 0) {
          _countdownSeconds -= 1;
        } else {
          _countdownComplete = true;
          timer.cancel();
        }
      });
    });
  }

  void _skipInstructions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Skip instructions?'),
        content: const Text(
          'Are you sure you want to skip instructions and proceed straight to analysis?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _startCamera();
            },
            child: const Text('Yes'),
          ),
        ],
      ),
    );
  }

  void _confirmReturnToHome() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Return to home screen?'),
        content: const Text(
          'Are you sure you want to return to home screen? Once you do, the results of this test are lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _countdownTimer?.cancel();
              setState(() {
                _showHomeScreen = true;
                _showStepFiveInstructions = false;
                _instructionStep = 1;
                _isCameraMode = false;
                _result = null;
                _countdownSeconds = _waitSeconds;
                _countdownComplete = false;
              });
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  String _formatCountdown() =>
      '${(_countdownSeconds ~/ 60).toString().padLeft(2, '0')}:${(_countdownSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(title: Text(_buildAppBarTitle()), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _buildCurrentView(),
      ),
    );
  }

  String _buildAppBarTitle() {
    if (_showHomeScreen) return 'Welcome';
    if (_showStepFiveInstructions) return 'Preparation Guide';
    if (_isCameraMode) return 'Camera Scan';
    if (_result != null) return 'Results';
    return 'Testing Procedure';
  }

  Widget _buildCurrentView() {
    if (_showHomeScreen) return _buildHomeScreen();
    if (_isAnalyzing) return _buildProcessingScreen();
    if (_showStepFiveInstructions && !_isCameraMode) {
      return _buildStepFiveReadyScreen();
    }
    if (_isCameraMode) return _buildCameraView();
    if (_result != null) return _buildResultsScreen(_result!);
    return _buildInstructionScreen();
  }

  Widget _buildHomeScreen() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Welcome to Strip Analyzer',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Follow the guided testing steps to prepare your sample, scan the strip, and review the result with confidence.',
              style: TextStyle(
                fontSize: 15,
                color: Colors.black54,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            _buildHeroPanel(),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _beginTestingProcedure,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Begin testing procedure'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _startDirectAnalysis,
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Go straight to analysis'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFB7D8FF)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick start',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'Choose to walk through the full preparation workflow or jump directly to the camera view.',
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionScreen() {
    const stepTitles = [
      'Step 1: Prepare the sample',
      'Step 2: Dip the strip',
      'Step 3: Wait for the strip',
      'Step 4: Lay the strip flat on an even surface',
      'Step 5: Analyze the strip',
    ];
    const stepDescriptions = [
      'Scoop 10 mg of your substance (about the size of a grain of rice) into 5 mL (same as 1 teaspoon) of water. Stir until fully dissolved.',
      'Remove the test strip from its packaging. Immerse the sample pad of the strip into the liquid. If the strip has a max line, do not immerse past that point. Remove after 15 to 30 seconds.',
      'Let the test strip rest 5 minutes before analyzing.',
      'Lay the test strip flat on the table, with the sample pad on the left and the end of the strip on the right. The proper orientation of the strip is shown below.',
      'Center the green box over the strip, as shown below. Your camera should be far enough from the strip so the test and control lines are in focus, but your phone should be close enough to the strip so that the length of the box is approximately 75% the length of the strip in the screen. Once the green box is aligned, tap the capture button to analyze the strip.',
    ];

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Card(
        key: ValueKey(_instructionStep),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stepTitles[_instructionStep - 1],
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                stepDescriptions[_instructionStep - 1],
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.black54,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              _buildInstructionIllustration(_instructionStep),
              const SizedBox(height: 20),
              if (_instructionStep == 3)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _countdownComplete
                        ? const Color(0xFFE8F5E9)
                        : const Color(0xFFF6F1E8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _countdownComplete
                          ? Colors.green.shade400
                          : Colors.orange.shade300,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _countdownComplete
                            ? 'Ready to proceed with analysis'
                            : 'Must wait five minutes before analyzing',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _countdownComplete
                              ? Colors.green.shade800
                              : Colors.orange.shade900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _countdownComplete
                            ? 'The waiting period is complete.'
                            : 'Time remaining: ${_formatCountdown()}',
                        style: TextStyle(
                          color: _countdownComplete
                              ? Colors.green.shade700
                              : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (_instructionStep > 1)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _goToPreviousStep,
                        child: const Text('Back'),
                      ),
                    ),
                  if (_instructionStep > 1) const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _instructionStep == 5
                          ? _startCamera
                          : _goToNextStep,
                      child: Text(
                        _instructionStep == 5
                            ? 'Open camera'
                            : 'Proceed to next step',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_instructionStep != 5)
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _skipInstructions,
                    child: const Text(
                      'Skip instructions and proceed to analysis',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepFiveReadyScreen() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Step 5: Analyze the strip',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Align the strip so the red lines are focused inside the green box. Ensure the phone is held level and no shadows are cast on the strip.',
              style: TextStyle(
                fontSize: 15,
                color: Colors.black54,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            _buildInstructionIllustration(5),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _startCamera,
                child: const Text('OK'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _goToPreviousStep,
                child: const Text('Back'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionIllustration(int step) {
    switch (step) {
      case 1:
      case 2:
        final asset = step == 1
            ? InstructionAnimations.dissolve
            : InstructionAnimations.dip;
        return GestureDetector(
          onTap: () => _openFullScreenAnimation(asset),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.52,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: HtmlAnimation(key: ValueKey(asset), assetPath: asset),
            ),
          ),
        );
      case 3:
        return Container(
          height: 180,
          decoration: BoxDecoration(
            color: _countdownComplete
                ? const Color(0xFFE8F5E9)
                : const Color(0xFFFFF8E8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _countdownComplete
                  ? Colors.green.shade400
                  : const Color(0xFFF3E3B7),
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 44,
                  color: _countdownComplete ? Colors.green : Colors.orange,
                ),
                const SizedBox(height: 10),
                Text(
                  _countdownComplete ? 'Ready' : _formatCountdown(),
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: _countdownComplete
                        ? Colors.green.shade800
                        : Colors.orange.shade900,
                  ),
                ),
              ],
            ),
          ),
        );
      case 4:
        return SizedBox(
          height: 180,
          width: double.infinity,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              'assets/images/App_example_image.png',
              fit: BoxFit.contain,
            ),
          ),
        );
      case 5:
      default:
        return Container(
          height: 180,
          decoration: BoxDecoration(
            color: const Color(0xFFF2FFF4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFCDEFD5)),
          ),
          child: Image.asset('assets/images/step_5.jpg', fit: BoxFit.contain),
        );
    }
  }

  void _openFullScreenAnimation(String asset) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.98,
          minChildSize: 0.35,
          maxChildSize: 0.99,
          builder: (context, controllerScroll) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Container(
                      width: 48,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                      child: HtmlAnimation(assetPath: asset),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildProcessingScreen() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            const CircularProgressIndicator(strokeWidth: 4),
            const SizedBox(height: 24),
            const Text(
              'Image received',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              'Your image is being processed. This may take a moment.',
              style: TextStyle(color: Colors.black54, height: 1.5),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: LinearProgressIndicator(
                minHeight: 8,
                backgroundColor: Colors.blue.shade100,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraView() {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: CameraPreview(controller),
              ),
              Positioned.fill(
                child: ColorFiltered(
                  colorFilter: const ColorFilter.mode(
                    Color.fromRGBO(0, 0, 0, 0.5),
                    BlendMode.srcOut,
                  ),
                  child: Stack(
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          color: Colors.black,
                          backgroundBlendMode: BlendMode.dstOut,
                        ),
                      ),
                      Align(
                        alignment: Alignment.center,
                        child: Container(
                          height: 50,
                          width: double.infinity,
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.center,
                child: Container(
                  height: 50,
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFF00FF00),
                      width: 3,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const Positioned(
                bottom: 20,
                child: Text(
                  'Center the green box over the strip',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            backgroundColor: const Color(0xFF007AFF),
          ),
          onPressed: _performCapture,
          child: const Text(
            'Capture Photo',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
        TextButton(
          onPressed: () => _stopCamera(returnToStep: true),
          child: const Text(
            'Cancel Camera',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _buildResultsScreen(AnalysisResult result) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _buildResultsCard(result),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _confirmReturnToHome,
                child: const Text('Return to home screen'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _badgeColors = {
    TestOutcome.positive: (Color(0xFFF8D7DA), Color(0xFF842029)),
    TestOutcome.negative: (Color(0xFFD1E7DD), Color(0xFF0F5132)),
    TestOutcome.invalid: (Color(0xFFFFF3CD), Color(0xFF664D03)),
  };

  Widget _buildResultsCard(AnalysisResult result) {
    final (badgeColor, badgeTextColor) = _badgeColors[result.outcome]!;
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
        border: const Border(
          left: BorderSide(color: Color(0xFF007AFF), width: 5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text(
              'Analysis Results',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(),
          const SizedBox(height: 10),
          Center(
            child: Column(
              children: [
                const Text(
                  'Test Outcome:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    result.outcome.label,
                    style: TextStyle(
                      color: badgeTextColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
          if (result.outcome != TestOutcome.invalid)
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'T/C Ratio: ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: result.tcRatio.toStringAsFixed(4)),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: 'Details: ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: result.interpretation),
              ],
            ),
          ),
          if (result.outcome != TestOutcome.invalid) ...[
            const SizedBox(height: 20),
            ProfileGraph(
              testProfile: result.test.profile,
              controlProfile: result.control.profile,
            ),
          ],
        ],
      ),
    );
  }
}
