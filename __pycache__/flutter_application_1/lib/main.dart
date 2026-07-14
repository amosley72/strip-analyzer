import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:webview_flutter/webview_flutter.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (cert, host, port) {
      return true;
    };
    return client;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  HttpOverrides.global = MyHttpOverrides();

  runApp(MaterialApp(
    home: StripAnalyzerScreen(cameras: cameras),
    theme: ThemeData(primarySwatch: Colors.blue),
    debugShowCheckedModeBanner: false,
  ));
}

class StripAnalyzerScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const StripAnalyzerScreen({super.key, required this.cameras});

  @override
  StripAnalyzerScreenState createState() => StripAnalyzerScreenState();
}

class StripAnalyzerScreenState extends State<StripAnalyzerScreen> {
  CameraController? _cameraController;
  XFile? _capturedFile;
  bool _isLoading = false;
  bool _isCameraMode = false;
  int _currentDilutionFactor = 1;
  Map<String, dynamic>? _analysisResults;

  bool _showHomeScreen = true;
  int _instructionStep = 1;
  bool _showStepFiveInstructions = false;
  Timer? _countdownTimer;
  int _countdownSeconds = 300;
  bool _countdownComplete = false;
  bool _showProcessingScreen = false;
  // HTML placeholders for steps 1 and 2. You can replace these by pasting your HTML strings.
  final String _stepHtml1 = r'''
 <!doctype html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Powder Dissolving Animation</title>
  <script src="https://cdn.tailwindcss.com/3.4.17"></script>
  <link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;700&amp;display=swap" rel="stylesheet">
  <style>
  body { font-family: 'DM Sans', sans-serif; }

  /* ---- Scene sizing ---- */
  .scene-wrap { width: 100%; max-width: 420px; margin: 0 auto; }
  .scene { position: relative; width: 100%; aspect-ratio: 1 / 1; }

  /* ---------- CUP ---------- */
  .cup-body {
    fill: rgba(255,255,255,0.28);
    stroke: rgba(255,255,255,0.85);
    stroke-width: 4;
  }
  .cup-glass-hi { fill: rgba(255,255,255,0.35); }

  /* ---------- LIQUID ---------- */
  .liquid {
    transform-box: fill-box;
    transform-origin: bottom;
    transform: scaleY(0);
    animation: liquidRise 12s linear infinite;
  }
  @keyframes liquidRise {
    0%, 18%   { transform: scaleY(0); }
    38%       { transform: scaleY(0.25); }
    100%      { transform: scaleY(0.25); }
  }

  .water-stream {
    opacity: 0;
    transform-box: fill-box;
    transform-origin: top;
    animation: streamFlow 12s linear infinite;
  }
  @keyframes streamFlow {
    0%, 18%   { opacity: 0; transform: scaleY(0); }
    20%       { opacity: 0.9; transform: scaleY(1); }
    36%       { opacity: 0.9; transform: scaleY(1); }
    40%,100%  { opacity: 0; transform: scaleY(0); }
  }

  .liquid-cloud {
    animation: cloudClear 12s linear infinite;
  }
  @keyframes cloudClear {
    0%, 38%  { opacity: 0; }
    45%      { opacity: 0.55; }
    78%      { opacity: 0.55; }
    92%,100% { opacity: 0; }
  }

  /* ---------- SCOOP ---------- */
  .scoop {
    transform-box: view-box;
    transform-origin: center;
    animation: scoopMove 12s ease-in-out infinite;
  }
  @keyframes scoopMove {
    0%      { transform: translate(-140px,-60px) rotate(-10deg); opacity: 0; }
    3%      { transform: translate(0px,-30px) rotate(-10deg); opacity: 1; }
    9%      { transform: translate(0px,-10px) rotate(-10deg); opacity: 1; }
    13%     { transform: translate(0px,-10px) rotate(28deg);  opacity: 1; }
    17%     { transform: translate(0px,-30px) rotate(-10deg); opacity: 1; }
    20%     { transform: translate(-140px,-60px) rotate(-10deg); opacity: 0; }
    100%    { transform: translate(-140px,-60px) rotate(-10deg); opacity: 0; }
  }

  .powder-fall {
    opacity: 0;
    transform-box: fill-box;
    animation: powderFall 12s linear infinite;
  }
  @keyframes powderFall {
    0%, 13%   { opacity: 0; transform: translateY(-40px); }
    14%       { opacity: 1; transform: translateY(-30px); }
    17%       { opacity: 1; transform: translateY(60px); }
    18%,100%  { opacity: 0; transform: translateY(60px); }
  }

  .powder-mound {
    animation: moundLife 12s linear infinite;
  }
  @keyframes moundLife {
    0%,14%   { opacity: 0; }
    17%      { opacity: 1; }
    40%      { opacity: 1; }
    55%      { opacity: 0.35; }
    100%     { opacity: 0; }
  }

  .particle {
    transform-box: fill-box;
    transform-origin: center;
    animation: particleLife 12s ease-in-out infinite;
  }
  @keyframes particleLife {
    0%,40%   { opacity: 0; }
    45%      { opacity: 0.9; }
    78%      { opacity: 0.4; }
    90%,100% { opacity: 0; }
  }
  .swirl-group {
    transform-box: view-box;
    transform-origin: 210px 300px;
    animation: swirl 12s linear infinite;
  }
  @keyframes swirl {
    0%,55%   { transform: rotate(0deg); }
    58%      { transform: rotate(90deg); }
    66%      { transform: rotate(360deg); }
    74%      { transform: rotate(630deg); }
    82%,100% { transform: rotate(720deg); }
  }

  /* ---------- SPOON ---------- */
  .spoon {
    transform-box: view-box;
    transform-origin: 210px 120px;
    animation: spoonStir 12s ease-in-out infinite;
    opacity: 0;
  }
  @keyframes spoonStir {
    0%,54%   { opacity: 0; transform: translateY(-40px) rotate(0deg); }
    56%      { opacity: 1; transform: translateY(0px) rotate(0deg); }
    60%      { opacity: 1; transform: translateY(0px) rotate(-14deg); }
    68%      { opacity: 1; transform: translateY(0px) rotate(14deg); }
    76%      { opacity: 1; transform: translateY(0px) rotate(-14deg); }
    82%      { opacity: 1; transform: translateY(0px) rotate(0deg); }
    85%      { opacity: 0; transform: translateY(-40px) rotate(0deg); }
    100%     { opacity: 0; transform: translateY(-40px) rotate(0deg); }
  }

  /* ---------- DISSOLVED CHECK ---------- */
  .done-badge {
    transform-box: fill-box;
    transform-origin: center;
    opacity: 0;
    animation: donePop 12s ease-out infinite;
  }
  @keyframes donePop {
    0%,86%   { opacity: 0; transform: scale(0.4); }
    90%      { opacity: 1; transform: scale(1.1); }
    94%      { opacity: 1; transform: scale(1); }
    99%      { opacity: 0.9; transform: scale(1); }
    100%     { opacity: 0; transform: scale(0.4); }
  }
</style>
</head>
<body class="min-h-screen w-full flex flex-col justify-center items-center" style="background: linear-gradient(160deg, rgb(234, 244, 249), rgb(214, 233, 242), rgb(195, 223, 236));">
  <main class="w-full px-4 py-12">
   <div class="max-w-4xl mx-auto">
    <section class="canva-card rounded-3xl p-6 sm:p-10 shadow-xl" style="background: linear-gradient(rgb(255, 255, 255), rgb(242, 249, 252));">
     <div class="scene-wrap">
      <div id="stage" class="stage scene">
       <svg viewBox="0 0 420 420" class="w-full h-full" aria-hidden="true">
        <defs>
         <clipPath id="cupClip">
          <path d="M120 150 L300 150 L280 360 Q210 380 140 360 Z"></path>
         </clipPath>
         <linearGradient id="waterGrad" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#7fd4e8"></stop>
          <stop offset="100%" stop-color="#3aa7c9"></stop>
         </linearGradient>
         <linearGradient id="scoopGrad" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" stop-color="#e9edf2"></stop>
          <stop offset="100%" stop-color="#c3ccd6"></stop>
         </linearGradient>
        </defs> 
        <ellipse cx="210" cy="378" rx="120" ry="16" fill="rgba(0,0,0,0.12)"></ellipse> 
        <g clip-path="url(#cupClip)">
         <rect class="liquid" x="120" y="200" width="180" height="180" fill="url(#waterGrad)"></rect> 
         <rect class="liquid-cloud" x="120" y="200" width="180" height="180" fill="#ffffff"></rect> 
         <g class="powder-mound">
          <ellipse cx="200" cy="352" rx="42" ry="12" fill="#f4d58d"></ellipse>
          <ellipse cx="200" cy="346" rx="30" ry="10" fill="#f0c766"></ellipse>
          <ellipse cx="210" cy="356" rx="26" ry="8" fill="#f4d58d"></ellipse>
         </g> 
         <g class="swirl-group">
          <circle class="particle" cx="180" cy="290" r="4" fill="#f0c766" style="animation-delay:0s"></circle>
          <circle class="particle" cx="240" cy="270" r="3" fill="#f4d58d" style="animation-delay:.2s"></circle>
          <circle class="particle" cx="200" cy="320" r="3.5" fill="#f0c766" style="animation-delay:.1s"></circle>
          <circle class="particle" cx="230" cy="330" r="3" fill="#f4d58d" style="animation-delay:.3s"></circle>
          <circle class="particle" cx="170" cy="330" r="2.5" fill="#f0c766" style="animation-delay:.15s"></circle>
          <circle class="particle" cx="255" cy="300" r="2.5" fill="#f4d58d" style="animation-delay:.25s"></circle>
         </g> 
         <rect class="water-stream" x="200" y="150" width="12" height="130" rx="6" fill="url(#waterGrad)"></rect> 
         <g>
          <circle class="powder-fall" cx="196" cy="200" r="4" fill="#f0c766" style="animation-delay:0s"></circle>
          <circle class="powder-fall" cx="206" cy="200" r="3" fill="#f4d58d" style="animation-delay:.15s"></circle>
          <circle class="powder-fall" cx="216" cy="200" r="3.5" fill="#f0c766" style="animation-delay:.3s"></circle>
          <circle class="powder-fall" cx="200" cy="200" r="2.5" fill="#f4d58d" style="animation-delay:.45s"></circle>
          <circle class="powder-fall" cx="212" cy="200" r="3" fill="#f0c766" style="animation-delay:.55s"></circle>
         </g>
        </g> 
        <path class="cup-body" d="M120 150 L300 150 L280 360 Q210 380 140 360 Z"></path> 
        <path class="cup-glass-hi" d="M140 160 L152 160 L142 350 Q136 350 132 348 Z"></path> 
        <g class="scoop">
         <rect x="192" y="60" width="8" height="70" rx="4" fill="url(#scoopGrad)"></rect>
         <path d="M170 130 Q196 172 222 130 Z" fill="url(#scoopGrad)" stroke="#aeb8c4" stroke-width="2"></path>
         <ellipse cx="196" cy="132" rx="26" ry="8" fill="#f0c766"></ellipse>
        </g> 
        <g class="spoon">
         <rect x="206" y="70" width="8" height="180" rx="4" fill="url(#scoopGrad)"></rect>
         <ellipse cx="210" cy="252" rx="18" ry="24" fill="url(#scoopGrad)" stroke="#aeb8c4" stroke-width="2"></ellipse>
        </g> 
        <g class="done-badge">
         <circle cx="330" cy="120" r="26" fill="#22c55e"></circle>
         <path d="M318 120 l8 9 l16 -18" fill="none" stroke="#ffffff" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"></path>
        </g>
       </svg>
      </div>
     </div>

     <p class="canva-text text-center mt-6" style="color: rgb(58, 96, 114); font-weight: 400; font-style: normal; font-size: 15px;">Watch the powder blend into the water until the mixture is clear and fully dissolved.</p>
    </section>
   </div>
  </main>
</body>
</html>

  ''';

  final String _stepHtml2 = r'''
<!doctype html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Test Strip Dip Animation</title>
  <script src="https://cdn.tailwindcss.com/3.4.17"></script>
  <script src="https://cdn.jsdelivr.net/npm/lucide@0.263.0/dist/umd/lucide.min.js"></script>
  <link href="https://fonts.googleapis.com/css2?family=Work+Sans:wght@400;500;600;700&amp;family=Space+Mono:wght@400;700&amp;display=swap" rel="stylesheet">
  <style>
  :root{
    --strip-w: 42px;
    --stage-h: 480px;
  }
  body { font-family: 'Work Sans', sans-serif; }

  .stage {
    position: relative;
    width: 100%;
    height: var(--stage-h);
    overflow: hidden;
  }

  /* ---- The test strip (pure CSS) ---- */
  .strip-wrap{
    position:absolute;
    left:50%;
    top:8px;
    transform: translateX(-50%);
    width: var(--strip-w);
    height: 300px;
    z-index: 5;
    will-change: transform;
  }
  
  .strip-wrap.play{ animation: dipCycle 26s ease-in-out forwards; }

  /* Tuned values: starts high out of water, dips only a tiny bit, and returns high */
  @keyframes dipCycle{
    0%   { transform: translateX(-50%) translateY(-75px); } 
    12%  { transform: translateX(-50%) translateY(-2px); }  
    18%  { transform: translateX(-50%) translateY(-2px); }
    88%  { transform: translateX(-50%) translateY(-2px); } 
    100% { transform: translateX(-50%) translateY(-75px); } 
  }

  .strip {
    position: relative;
    width: 100%;
    height: 100%;
    border-radius: 6px 6px 4px 4px;
    background: linear-gradient(180deg,#ffffff 0%,#ffffff 55%, #f4f4f4 55%, #f4f4f4 100%);
    box-shadow: 0 6px 14px rgba(0,0,0,.18);
    border:1px solid #e2e2e2;
    overflow:hidden;
  }
  /* red label band near top (handle) */
  .strip::before{
    content:"";
    position:absolute;
    top:14px;left:0;right:0;height:26px;
    background: linear-gradient(180deg,#e11d2a,#b5121e);
  }
  /* lower white / clear sample region (the dipped tip end) */
  .strip .tip{
    position:absolute;
    bottom:0;left:0;right:0;height:70px;
    background: linear-gradient(180deg,#f5f5f5,#e8e8e8);
  }

  /* Black MAX Line drawn directly on the strip body */
  .max-line-strip {
    position: absolute;
    bottom: 70px; 
    left: 0;
    right: 0;
    height: 2px;
    background-color: #011222;
    display: flex;
    justify-content: center;
    align-items: center;
    z-index: 10;
  }
  .max-line-strip span {
    font-family: 'Space Mono', monospace;
    font-size: 9px;
    font-weight: 700;
    color: #ffffff;
    background-color: #011222;
    padding: 0px 3px;
    border-radius: 2px;
    transform: translateY(-1px);
    letter-spacing: 0.5px;
  }

  /* result window with C/T bands */
  .result-window{
    position:absolute;
    top:70px;left:8px;right:8px;height:56px;
    background:#fbfbf6;
    border:1px solid #dcdcd2;
    border-radius:3px;
    display:flex;flex-direction:column;justify-content:center;gap:7px;
    padding:0 6px;
  }
  .band{ height:5px;border-radius:2px;background:#d13a4a;opacity:0;transition:opacity .8s ease; }
  .strip-wrap.developed .band.c{ opacity:.95; }
  .strip-wrap.developed .band.t{ opacity:.65; }

  /* ---- Cup + liquid ---- */
  .cup-area{
    position:absolute;
    left:50%; 
    bottom:95px; 
    transform:translateX(-50%);
    width:150px; height:150px;
    z-index:4;
  }
  .cup{
    position:absolute; inset:0;
    border:3px solid #cfd8dc;
    border-top:none;
    border-radius:6px 6px 16px 16px;
    background: linear-gradient(180deg, rgba(255,255,255,.35), rgba(236,244,246,.55));
    box-shadow: inset 0 -8px 16px rgba(0,0,0,.05), 0 8px 20px rgba(0,0,0,.12);
    overflow:hidden;
  }
  .cup-rim{
    position:absolute; top:-6px; left:-6px; right:-6px; height:12px;
    border-radius:50%;
    border:3px solid #cfd8dc;
    background: rgba(255,255,255,.5);
    z-index:6;
  }
  .liquid{
    position:absolute; left:0; right:0; bottom:0;
    height:34%;
    background: linear-gradient(180deg, rgba(120,200,225,.55), rgba(70,160,200,.75));
  }
  .liquid .surface{
    position:absolute; top:0; left:0; right:0; height:6px;
    background: rgba(255,255,255,.45);
    animation: ripple 3.5s ease-in-out infinite;
  }
  @keyframes ripple{
    0%,100%{ transform: scaleY(1); opacity:.5; }
    50%{ transform: scaleY(1.6); opacity:.85; }
  }
  .cup-area.splash .liquid .surface{ animation: rippleFast 1s ease-out 2; }
  @keyframes rippleFast{
    0%{ transform: scaleY(2.4); opacity:1; }
    100%{ transform: scaleY(1); opacity:.5; }
  }

  /* progress ring */
  .ring{ transform: rotate(-90deg); }
  .ring circle{ fill:none; stroke-width:6; }
  .ring .track{ stroke:#e2e8f0; }
  .ring .fill{ stroke:#0f766e; stroke-linecap:round; transition: stroke-dashoffset .2s linear; }

  @media (max-width: 640px){
    :root{ --stage-h: 400px; }
  }
</style>
</head>
<body class="min-h-screen w-full flex items-center justify-center" style="background: linear-gradient(160deg, rgb(240, 247, 246), rgb(230, 239, 242), rgb(219, 233, 238));">
  <div class="w-full max-w-2xl mx-auto px-5 py-8">
   <main class="flex flex-col gap-6 items-stretch">
    <section class="canva-panel rounded-2xl p-4 shadow-sm relative" style="background: rgb(255, 255, 255);">
     
     <div class="absolute top-4 left-4 z-20 flex items-center gap-3 bg-white/80 backdrop-blur-sm p-2 rounded-xl border border-slate-100 shadow-sm">
       <div class="relative w-12 h-12">
        <svg class="ring w-12 h-12" viewBox="0 0 150 150" aria-hidden="true">
         <circle class="track" cx="75" cy="75" r="66"></circle> 
         <circle id="ring-fill" class="fill" cx="75" cy="75" r="66"></circle>
        </svg>
        <div class="absolute inset-0 flex items-center justify-center">
         <span id="count" class="font-bold text-sm" style="font-family:'Space Mono',monospace; color:#0f766e">0s</span>
        </div>
       </div>
     </div>

     <div class="stage">
      <div id="strip" class="strip-wrap">
       <div class="strip">
        <div class="result-window">
         <span class="band c"></span> <span class="band t"></span>
        </div>
        <div class="max-line-strip"><span>MAX</span></div>
        <div class="tip"></div>
       </div>
      </div>
      <div id="cup" class="cup-area">
       <div class="cup-rim"></div>
       <div class="cup">
        <div class="liquid">
         <div class="surface"></div>
        </div>
       </div>
      </div>
     </div>
    </section>
    
    <div class="flex justify-center">
      <button id="replay" type="button" class="canva-button inline-flex items-center gap-2 px-6 py-2.5 rounded-full font-semibold shadow-sm hover:opacity-90 transition focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-teal-500" style="background: rgb(15, 118, 110); color: rgb(255, 255, 255);"> 
        <i data-lucide="rotate-ccw" style="width:18px;height:18px"></i> 
        <span style="color: rgb(255, 255, 255); font-weight: 600; font-style: normal; font-size: 16px;">Replay Animation</span> 
      </button>
    </div>
   </main>
  </div>

  <script>
    lucide.createIcons();

    const strip = document.getElementById('strip');
    const cup = document.getElementById('cup');
    const countEl = document.getElementById('count');
    const ringFill = document.getElementById('ring-fill');

    const R = 66;
    const CIRC = 2 * Math.PI * R;
    ringFill.style.strokeDasharray = CIRC;
    ringFill.style.strokeDashoffset = CIRC;

    const T = {
      lowerEnd: 3120,   
      soakStart: 4680,  
      soakEnd: 22880,   
      total: 26000
    };
    const SOAK_TARGET = 22; 

    let raf = null;
    let startTs = null;

    function reset(){
      if (raf) cancelAnimationFrame(raf);
      strip.classList.remove('play','developed');
      cup.classList.remove('splash');
      void strip.offsetWidth;
      countEl.textContent = '0s';
      ringFill.style.strokeDashoffset = CIRC;
    }

    function play(){
      reset();
      strip.classList.add('play');
      startTs = performance.now();
      let splashed = false, developed = false;

      function frame(now){
        const el = now - startTs;

        if (!splashed && el >= T.lowerEnd){
          splashed = true;
          cup.classList.add('splash');
        }

        if (el < T.soakStart){
          countEl.textContent = '0s';
        } else if (el <= T.soakEnd){
          if (!developed && el >= T.soakStart + 2500){
            developed = true;
            strip.classList.add('developed'); 
          }
          const p = (el - T.soakStart) / (T.soakEnd - T.soakStart); 
          const secs = Math.min(SOAK_TARGET, Math.round(p * SOAK_TARGET));
          countEl.textContent = secs + 's';
          ringFill.style.strokeDashoffset = CIRC * (1 - Math.min(1, p));
        } else {
          countEl.textContent = SOAK_TARGET + 's';
          ringFill.style.strokeDashoffset = 0;
        }

        if (el < T.total){
          raf = requestAnimationFrame(frame);
        }
      }
      raf = requestAnimationFrame(frame);
    }

    document.getElementById('replay').addEventListener('click', () => {
      play();
    });

    play();
  </script>
</body>
</html>
  ''';

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _startCamera() async {
    if (widget.cameras.isEmpty) return;

    final backCamera = widget.cameras.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.back,
      orElse: () => widget.cameras.first,
    );

    _cameraController = CameraController(
      backCamera,
      ResolutionPreset.max,
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      await _cameraController!.setFocusMode(FocusMode.auto);
      await _cameraController!.setZoomLevel(2.0);

      setState(() {
        _showHomeScreen = false;
        _showStepFiveInstructions = false;
        _isCameraMode = true;
        _instructionStep = 5;
      });
    } catch (e) {
      _showSnackBar('Camera initialization failed: $e');
    }
  }

  void _stopCamera({bool returnToStep = true}) {
    _countdownTimer?.cancel();
    setState(() {
      _isCameraMode = false;
      _cameraController?.dispose();
      _cameraController = null;
      if (returnToStep) {
        _showHomeScreen = false;
        _showStepFiveInstructions = false;
        _instructionStep = 5;
      }
    });
  }

  Future<void> _performCapture() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    try {
      final file = await _cameraController!.takePicture();

      setState(() {
        _isLoading = true;
        _showProcessingScreen = true;
      });

      final croppedFile = await _cropToGreenBox(file);

      setState(() {
        _capturedFile = XFile(croppedFile.path);
        _isCameraMode = false;
      });
      _stopCamera(returnToStep: false);
      _uploadAndAnalyze();
    } catch (e) {
      _showSnackBar('Capture failed: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<File> _cropToGreenBox(XFile rawPhoto) async {
    final bytes = await rawPhoto.readAsBytes();
    img.Image? decodedImage = img.decodeImage(bytes);
    if (decodedImage == null) return File(rawPhoto.path);

    final imageWidth = decodedImage.width;
    final imageHeight = decodedImage.height;
    final cropWidth = (imageWidth * 0.95).toInt();
    final cropHeight = (imageHeight * 0.12).toInt();
    final cropX = ((imageWidth - cropWidth) / 2).toInt();
    final cropY = ((imageHeight - cropHeight) / 2).toInt();

    final croppedImage = img.copyCrop(
      decodedImage,
      x: cropX,
      y: cropY,
      width: cropWidth,
      height: cropHeight,
    );

    final croppedFile = File(rawPhoto.path);
    await croppedFile.writeAsBytes(img.encodeJpg(croppedImage, quality: 80));

    return croppedFile;
  }

  Future<void> _uploadAndAnalyze() async {
    if (_capturedFile == null) return;

    setState(() {
      _isLoading = true;
      _analysisResults = null;
      _showProcessingScreen = true;
    });

    try {
      final uri = Uri.parse('https://172.20.10.14:8001/analyze');
      final request = http.MultipartRequest('POST', uri);

      request.fields['dilution_factor'] = _currentDilutionFactor.toString();
      request.files.add(await http.MultipartFile.fromPath('file', _capturedFile!.path));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _analysisResults = data;
        });

        final concentration = double.tryParse(data['estimated_concentration_mg_ml'].toString()) ?? 0.0;
        if (concentration >= 2.0) {
          _showOverflowModal();
        }
      } else {
        throw Exception('Server status error: ${response.statusCode}');
      }
    } catch (e) {
      _showSnackBar('Analysis failed: $e');
    } finally {
      setState(() {
        _isLoading = false;
        _showProcessingScreen = false;
      });
    }
  }

  void _showOverflowModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Concentration Exceeds 2 mg/mL', style: TextStyle(color: Colors.red)),
        content: const Text('Dilute solution and retest in order to determine lower concentration.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showInstructionsModal();
            },
            child: const Text('Dilute & Retest', style: TextStyle(color: Colors.green)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  void _showInstructionsModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Dilution Procedure Instructions', style: TextStyle(color: Colors.blue)),
        content: const Text(
          'Take 1 mL of the solution previously tested and add 9 mL of water to it. Mix vigorously.\n\nInsert another test strip and repeat the validation scanning procedure.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _currentDilutionFactor *= 10;
              });
              _startCamera();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _quitDilutionSchema() {
    setState(() {
      _currentDilutionFactor = 1;
      _analysisResults = null;
      _capturedFile = null;
    });
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _beginTestingProcedure() {
    setState(() {
      _showHomeScreen = false;
      _instructionStep = 1;
      _showStepFiveInstructions = false;
      _countdownComplete = false;
      _countdownSeconds = 300;
      _isCameraMode = false;
      _showProcessingScreen = false;
    });
    _countdownTimer?.cancel();
  }

  void _startDirectAnalysis() {
    setState(() {
      _showHomeScreen = false;
      _instructionStep = 5;
      _showStepFiveInstructions = true;
      _isCameraMode = false;
      _countdownComplete = false;
      _countdownSeconds = 300;
      _showProcessingScreen = false;
    });
    _countdownTimer?.cancel();
  }

  void _goToNextStep() {
    if (_instructionStep < 5) {
      setState(() {
        _instructionStep += 1;
        _showStepFiveInstructions = false;
        _countdownComplete = false;
        _countdownSeconds = 300;
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
        _countdownSeconds = 300;
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
        _showProcessingScreen = false;
      });
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _countdownSeconds = 300;
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
        content: const Text('Are you sure you want to skip instructions and proceed straight to analysis?'),
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
        content: const Text('Are you sure you want to return to home screen? Once you do, the results of this test are lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _showHomeScreen = true;
                _showStepFiveInstructions = false;
                _instructionStep = 1;
                _isCameraMode = false;
                _analysisResults = null;
                _capturedFile = null;
                _countdownSeconds = 300;
                _countdownComplete = false;
              });
              _countdownTimer?.cancel();
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Color _getBadgeColor(String status) {
    if (status == 'POSITIVE') return const Color(0xFFF8D7DA);
    if (status == 'NEGATIVE') return const Color(0xFFD1E7DD);
    return const Color(0xFFFFF3CD);
  }

  Color _getBadgeTextColor(String status) {
    if (status == 'POSITIVE') return const Color(0xFF842029);
    if (status == 'NEGATIVE') return const Color(0xFF0F5132);
    return const Color(0xFF664D03);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: Text(_buildAppBarTitle()),
        centerTitle: true,
      ),
      body: Column(
        children: [
          if (_currentDilutionFactor > 1)
            Container(
              color: const Color(0xFFD93838),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              width: double.infinity,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '⚠️ DILUTION MODE ACTIVE (${_currentDilutionFactor}x)',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFFD93838)),
                    onPressed: _quitDilutionSchema,
                    child: const Text('QUIT SCHEMA', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildCurrentView(),
            ),
          ),
        ],
      ),
    );
  }

  String _buildAppBarTitle() {
    if (_showHomeScreen) return 'Welcome';
    if (_showStepFiveInstructions) return 'Preparation Guide';
    if (_isCameraMode) return 'Camera Scan';
    if (_analysisResults != null) return 'Results';
    return 'Testing Procedure';
  }

  Widget _buildCurrentView() {
    if (_showHomeScreen) return _buildHomeScreen();
    if (_showProcessingScreen) return _buildProcessingScreen();
    if (_showStepFiveInstructions && !_isCameraMode) return _buildStepFiveReadyScreen();
    if (_isCameraMode) return _buildCameraView();
    if (_analysisResults != null) return _buildResultsScreen();
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
              style: TextStyle(fontSize: 15, color: Colors.black54, height: 1.5),
            ),
            const SizedBox(height: 24),
            _buildHeroPanel(),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _beginTestingProcedure,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Begin testing procedure'),
                    style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _startDirectAnalysis,
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Go straight to analysis'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text('Quick start', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('Choose to walk through the full preparation workflow or jump directly to the camera view.'),
        ],
      ),
    );
  }

  Widget _buildInstructionScreen() {
    final stepTitles = [
      'Step 1: Prepare the sample',
      'Step 2: Dip the strip',
      'Step 3: Wait for the strip',
      'Step 4: Lay the strip flat on an even surface',
      'Step 5: Analyze the strip',
    ];
    final stepDescriptions = [
      'Scoop 10 mg of your substance (about the size of a grain of rice) into 5 mL (same as 1 teaspoon) of water. Stir until fully dissolved.',
      'Remove the test strip from its packaging. Immerse the sample pad of the strip into the liquid. If the strip has a max line, do not immerse past that point. Remove after 15 to 30 seconds.',
      'Let the test strip rest 5 minutes before analyzing.',
      'Lay the test strip flat on the table, with the sample pad on the left and the end of the strip on the right.',
      'Center the green box over the strip. Your camera should be far enough from the strip so the test and control lines are in focus, but your phone should be close enough to the strip so that the length of the box is approximately 75% the length of the strip in the screen. Once the green box is aligned, tap the capture button to analyze the strip.'
,
    ];

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey(_instructionStep),
        child: Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stepTitles[_instructionStep - 1],
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  stepDescriptions[_instructionStep - 1],
                  style: const TextStyle(fontSize: 15, color: Colors.black54, height: 1.5),
                ),
                const SizedBox(height: 20),
                _buildInstructionIllustration(_instructionStep),
                const SizedBox(height: 20),
                if (_instructionStep == 3)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _countdownComplete ? const Color(0xFFE8F5E9) : const Color(0xFFF6F1E8),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _countdownComplete ? Colors.green.shade400 : Colors.orange.shade300),
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
                            color: _countdownComplete ? Colors.green.shade800 : Colors.orange.shade900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _countdownComplete
                              ? 'The waiting period is complete.'
                              : 'Time remaining: ${(_countdownSeconds ~/ 60).toString().padLeft(2, '0')}:${(_countdownSeconds % 60).toString().padLeft(2, '0')}',
                          style: TextStyle(color: _countdownComplete ? Colors.green.shade700 : Colors.black54),
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
                        onPressed: _instructionStep == 5 ? _startCamera : _goToNextStep,
                        child: Text(_instructionStep == 5 ? 'Open camera' : 'Proceed to next step'),
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
                      child: const Text('Skip instructions and proceed to analysis'),
                    ),
                  ),
              ],
            ),
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
            const Text('Step 5: Analyze the strip', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text(
              'Align the strip so the red lines are focused inside the green box. Ensure the phone is held level and no shadows are cast on the strip.',
              style: TextStyle(fontSize: 15, color: Colors.black54, height: 1.5),
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
    final double webviewHeight = (step == 1 || step == 2)
      ? MediaQuery.of(context).size.height * 0.52
      : MediaQuery.of(context).size.height * 0.32;
    switch (step) {
      case 1:
        return GestureDetector(
          onTap: () => _openFullScreenHtml(1),
          child: SizedBox(
            height: webviewHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _buildHtmlAnimationWidget(_stepHtml1),
            ),
          ),
        );
      case 2:
        return GestureDetector(
          onTap: () => _openFullScreenHtml(2),
          child: SizedBox(
            height: webviewHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _buildHtmlAnimationWidget(_stepHtml2),
            ),
          ),
        );
      case 3:
        return Container(
          height: 180,
          decoration: BoxDecoration(
            color: _countdownComplete ? const Color(0xFFE8F5E9) : const Color(0xFFFFF8E8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _countdownComplete ? Colors.green.shade400 : const Color(0xFFF3E3B7)),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.timer_outlined, size: 44, color: _countdownComplete ? Colors.green : Colors.orange),
                const SizedBox(height: 10),
                Text(
                  _countdownComplete ? 'Ready' : '${(_countdownSeconds ~/ 60).toString().padLeft(2, '0')}:${(_countdownSeconds % 60).toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: _countdownComplete ? Colors.green.shade800 : Colors.orange.shade900,
                  ),
                ),
              ],
            ),
          ),
        );
      case 4:
        return const SizedBox.shrink();
      case 5:
      default:
        return Container(
          height: 180,
          decoration: BoxDecoration(
            color: const Color(0xFFF2FFF4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFCDEFD5)),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.center_focus_strong, size: 46, color: Colors.green),
                SizedBox(height: 10),
                Text('Position the strip in the green guide box', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        );
    }
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
            const Text('Image received', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text('Your image is being processed. This may take a moment.', style: TextStyle(color: Colors.black54, height: 1.5)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: LinearProgressIndicator(minHeight: 8, backgroundColor: Colors.blue.shade100, valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600)),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildHtmlAnimationWidget(String html) {
    final String strippedHtml = '$html<script>window.addEventListener("DOMContentLoaded",function(){try{document.querySelectorAll("p,h1,h2,h3,h4,h5, .instruction, .instructions, .caption, .label, .note").forEach(e=>e.remove());}catch(e){} });</script>';

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadHtmlString(strippedHtml);

    return WebViewWidget(controller: controller);
  }

  void _openFullScreenHtml(int step) {
    String html = (step == 1) ? _stepHtml1 : _stepHtml2;
    // Instructions intentionally omitted here — we only display the animation in the bottom half.
    final String strippedHtml = '$html<script>window.addEventListener("DOMContentLoaded",function(){try{document.querySelectorAll("p,h1,h2,h3,h4,h5, .instruction, .instructions, .caption, .label, .note").forEach(e=>e.remove());}catch(e){} });</script>';

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadHtmlString(strippedHtml);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        // Make steps 1 and 2 open nearly full-screen by default
        final bool fullScreenDefault = (step == 1 || step == 2);
        final double initialSize = fullScreenDefault ? 0.98 : 0.65;
        final double minSize = fullScreenDefault ? 0.35 : 0.35;
        final double maxSize = fullScreenDefault ? 0.99 : 0.95;

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: initialSize,
          minChildSize: minSize,
          maxChildSize: maxSize,
          builder: (context, controllerScroll) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  // small handle
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(3))),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      child: WebViewWidget(controller: controller),
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

  Widget _buildCameraView() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
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
                aspectRatio: _cameraController!.value.aspectRatio,
                child: CameraPreview(_cameraController!),
              ),
              Positioned.fill(
                child: ColorFiltered(
                  colorFilter: const ColorFilter.mode(Color.fromRGBO(0, 0, 0, 0.5), BlendMode.srcOut),
                  child: Stack(
                    children: [
                      Container(decoration: const BoxDecoration(color: Colors.black, backgroundBlendMode: BlendMode.dstOut)),
                      Align(
                        alignment: Alignment.center,
                        child: Container(
                          height: 50,
                          width: double.infinity,
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
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
                    border: Border.all(color: const Color(0xFF00FF00), width: 3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const Positioned(
                bottom: 20,
                child: Text('Center the green box over the strip', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: const Color(0xFF007AFF)),
          onPressed: _performCapture,
          child: const Text('Capture Photo', style: TextStyle(color: Colors.white, fontSize: 16)),
        ),
        TextButton(onPressed: () => _stopCamera(returnToStep: true), child: const Text('Cancel Camera', style: TextStyle(color: Colors.grey))),
      ],
    );
  }

  Widget _buildResultsScreen() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('Analyzing image on cloud server...', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
              ),
            if (_analysisResults != null) _buildResultsCard(),
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

  Widget _buildResultsCard() {
    final res = _analysisResults!;
    final qualitative = res['qualitative_result'] ?? 'INVALID';

    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
        border: const Border(left: BorderSide(color: Color(0xFF007AFF), width: 5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: Text('Analysis Results', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          const Divider(),
          const SizedBox(height: 10),
          Center(
            child: Column(
              children: [
                const Text('Test Outcome:', style: TextStyle(fontWeight: FontWeight.bold)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: _getBadgeColor(qualitative),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    qualitative,
                    style: TextStyle(color: _getBadgeTextColor(qualitative), fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
          Text.rich(TextSpan(children: [const TextSpan(text: 'T/C Ratio: ', style: TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: '${res['tc_ratio']}')])),
          Text.rich(TextSpan(children: [const TextSpan(text: 'Concentration (Current Strip): ', style: TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: '${res['estimated_concentration_mg_ml']} mg/mL')])),
          if (_currentDilutionFactor > 1 && res['original_concentration_mg_ml'] != null)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFFFF3CD), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFFFEEBA))),
              child: Text.rich(TextSpan(children: [const TextSpan(text: 'Concentration in original solution: ', style: TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: '${res['original_concentration_mg_ml']} mg/mL', style: const TextStyle(color: Color(0xFFB91C1C)))])),
            ),
          const SizedBox(height: 10),
          Text.rich(TextSpan(children: [const TextSpan(text: 'Details: ', style: TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: '${res['interpretation']}')])),
          if (res['profile_graph'] != null && qualitative != 'INVALID') ...[
            const SizedBox(height: 20),
            _buildProfileGraph(
              res['profile_graph'] as Map<String, dynamic>,
              isZeroRatio: double.tryParse(res['tc_ratio']?.toString() ?? '') == 0,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProfileGraph(Map<String, dynamic> graphData, {bool isZeroRatio = false}) {
    final rawControlProfile = _parseProfileValues(graphData['control_profile']);
    final rawTestProfile = _parseProfileValues(graphData['test_profile']);
    final testPeakLabel = graphData['peak_label']?.toString() ?? 'Peak Label';

    if (isZeroRatio) {
      final graphControlProfile = _buildZeroRatioControlProfile(rawControlProfile);
      final graphTestProfile = List<double>.filled(graphControlProfile.length, 0.0);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Graph of Intensities of Test and Control Lines', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            height: 220,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: CustomPaint(
                painter: _ProfileGraphPainter(
                  testProfile: graphTestProfile,
                  controlProfile: graphControlProfile,
                  peakLabel: testPeakLabel,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildLegendDot(Colors.blue, 'Test Line'),
              const SizedBox(width: 16),
              _buildLegendDot(Colors.green, 'Control Line'),
              const SizedBox(width: 16),
            ],
          ),
          const SizedBox(height: 12),
          Text('Parsed backend graph values:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 4),
          Text('control_profile: $rawControlProfile', style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 2),
          Text('test_profile: $rawTestProfile', style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      );
    }

    final controlProfile = _expandSingleValueProfile(rawControlProfile);
    final testProfile = _expandSingleValueProfile(rawTestProfile);
    if (controlProfile.isEmpty || testProfile.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Graph of Intensities of Test and Control Lines', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          height: 220,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: CustomPaint(
              painter: _ProfileGraphPainter(
                testProfile: testProfile,
                controlProfile: controlProfile,
                peakLabel: testPeakLabel,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildLegendDot(Colors.blue, 'Test Line'),
            const SizedBox(width: 16),
            _buildLegendDot(Colors.green, 'Control Line'),
            const SizedBox(width: 16),
          ],
        ),
        const SizedBox(height: 12),
        Text('Parsed backend graph values:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
        const SizedBox(height: 4),
        Text('control_profile: $rawControlProfile', style: const TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 2),
        Text('test_profile: $rawTestProfile', style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black87)),
      ],
    );
  }

  List<double> _parseProfileValues(dynamic values) {
    if (values is num) {
      final valueDouble = values.toDouble();
      return valueDouble == -1.0 ? <double>[] : [valueDouble];
    }

    if (values is List) {
      return values
          .map((value) {
            if (value is num) {
              final valueDouble = value.toDouble();
              return valueDouble == -1.0 ? null : valueDouble;
            }
            if (value is String) {
              final parsed = double.tryParse(value.trim());
              return parsed == -1.0 ? null : parsed;
            }
            return null;
          })
          .where((value) => value != null)
          .cast<double>()
          .toList();
    }

    if (values is String) {
      final trimmed = values.trim();
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is num) {
          final valueDouble = decoded.toDouble();
          return valueDouble == -1.0 ? <double>[] : [valueDouble];
        }
        if (decoded is List) {
          return decoded
              .map((value) {
                if (value is num) {
                  final valueDouble = value.toDouble();
                  return valueDouble == -1.0 ? null : valueDouble;
                }
                if (value is String) {
                  final parsed = double.tryParse(value.trim());
                  return parsed == -1.0 ? null : parsed;
                }
                return null;
              })
              .where((value) => value != null)
              .cast<double>()
              .toList();
        }
      } catch (_) {
        // Fall through and try manual parsing.
      }

      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        final inner = trimmed.substring(1, trimmed.length - 1);
        return inner
            .split(',')
            .map((item) => double.tryParse(item.trim()))
            .where((value) => value != null && value != -1.0)
            .cast<double>()
            .toList();
      }

      final parsed = double.tryParse(trimmed);
      if (parsed != null && parsed != -1.0) {
        return [parsed];
      }
    }

    return <double>[];
  }

  List<double> _buildSyntheticControlProfile() {
    return const [0.1, 0.25, 0.45, 0.6, 0.75, 0.85, 0.8, 0.7, 0.55, 0.4];
  }

  List<double> _buildZeroRatioControlProfile(List<double> rawControlProfile) {
    if (rawControlProfile.isEmpty) {
      return _buildSyntheticControlProfile();
    }
    return _expandSingleValueProfile(rawControlProfile);
  }

  List<double> _expandSingleValueProfile(List<double> profile) {
    if (profile.length != 1) {
      return profile;
    }

    final intensity = profile.first.clamp(0.0, 1.0);
    return [
      intensity * 0.05,
      intensity * 0.2,
      intensity * 0.4,
      intensity * 0.7,
      intensity,
      intensity * 0.8,
      intensity * 0.55,
    ];
  }
}

class _ProfileGraphPainter extends CustomPainter {
  final List<double> testProfile;
  final List<double> controlProfile;
  final String peakLabel;

  _ProfileGraphPainter({required this.testProfile, required this.controlProfile, required this.peakLabel});

  @override
  void paint(Canvas canvas, Size size) {
    final paintBackground = Paint()..color = const Color(0xFFF8F9FA);
    canvas.drawRect(Offset.zero & size, paintBackground);

    final allValues = <double>[...testProfile, ...controlProfile];
    if (allValues.isEmpty) return;

    const minY = 0.0;
    const maxY = 1.0;
    const normalizedRange = 1.0;

    const leftPadding = 28.0;
    const rightPadding = 12.0;
    const topPadding = 16.0;
    const bottomPadding = 24.0;
    final chartWidth = size.width - leftPadding - rightPadding;
    final chartHeight = size.height - topPadding - bottomPadding;
    final axisPaint = Paint()..color = Colors.black12..strokeWidth = 1;
    final gridPaint = Paint()..color = Colors.black12..strokeWidth = 0.5;
    const gridLines = 4;

    for (var i = 0; i <= gridLines; i++) {
      final y = topPadding + chartHeight * i / gridLines;
      canvas.drawLine(Offset(leftPadding, y), Offset(size.width - rightPadding, y), gridPaint);
    }

    canvas.drawLine(Offset(leftPadding, topPadding), Offset(leftPadding, size.height - bottomPadding), axisPaint);
    canvas.drawLine(Offset(leftPadding, size.height - bottomPadding), Offset(size.width - rightPadding, size.height - bottomPadding), axisPaint);

    void drawProfile(List<double> values, Color color) {
      if (values.isEmpty) return;
      final linePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round;

      if (values.length == 1) {
        final x = leftPadding + chartWidth / 2;
        final normalizedY = ((values.first.clamp(0.0, 1.0)) - minY) / normalizedRange;
        final y = size.height - bottomPadding - normalizedY * chartHeight;
        canvas.drawCircle(Offset(x, y), 4.0, linePaint..style = PaintingStyle.fill);
        return;
      }

      final path = Path();
      final step = chartWidth / (values.length - 1);
      for (var i = 0; i < values.length; i++) {
        final x = leftPadding + step * i;
        final normalizedY = ((values[i].clamp(0.0, 1.0)) - minY) / normalizedRange;
        final y = size.height - bottomPadding - normalizedY * chartHeight;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, linePaint);
    }

    drawProfile(controlProfile, Colors.green.shade700);
    drawProfile(testProfile, Colors.blue.shade700);

    const labelStyle = TextStyle(color: Colors.black54, fontSize: 10);
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i <= gridLines; i++) {
      final labelValue = maxY - i * normalizedRange / gridLines;
      textPainter.text = TextSpan(text: labelValue.toStringAsFixed(2), style: labelStyle);
      textPainter.layout(minWidth: 0, maxWidth: leftPadding - 4);
      final y = topPadding + chartHeight * i / gridLines - textPainter.height / 2;
      textPainter.paint(canvas, Offset(0, y));
    }

  }

  @override
  bool shouldRepaint(covariant _ProfileGraphPainter oldDelegate) {
    return oldDelegate.testProfile.length != testProfile.length ||
        oldDelegate.controlProfile.length != controlProfile.length ||
        oldDelegate.peakLabel != peakLabel ||
        !_listEquals(oldDelegate.testProfile, testProfile) ||
        !_listEquals(oldDelegate.controlProfile, controlProfile);
  }

  bool _listEquals(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }}