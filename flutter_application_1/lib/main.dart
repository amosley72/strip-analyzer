import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'screens/strip_analyzer_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(
    MaterialApp(
      home: StripAnalyzerScreen(cameras: cameras),
      theme: ThemeData(primarySwatch: Colors.blue),
      debugShowCheckedModeBanner: false,
    ),
  );
}
