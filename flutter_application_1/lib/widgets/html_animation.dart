import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Instruction animations bundled as self-contained HTML (no network needed).
class InstructionAnimations {
  static const dissolve = 'assets/html/step1_dissolve.html';
  static const dip = 'assets/html/step2_dip.html';
}

/// Shows a bundled HTML animation. The WebView controller is created once per
/// widget, not on every rebuild.
class HtmlAnimation extends StatefulWidget {
  final String assetPath;
  const HtmlAnimation({super.key, required this.assetPath});

  @override
  State<HtmlAnimation> createState() => _HtmlAnimationState();
}

class _HtmlAnimationState extends State<HtmlAnimation> {
  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..loadFlutterAsset(widget.assetPath);

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}
