import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Plots the measured absorbance profiles across the test and control lines,
/// both scaled to the larger of the two peaks.
class ProfileGraph extends StatelessWidget {
  final List<double> testProfile;
  final List<double> controlProfile;

  const ProfileGraph({
    super.key,
    required this.testProfile,
    required this.controlProfile,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Graph of Intensities of Test and Control Lines',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          height: 220,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: CustomPaint(
              painter: _ProfileGraphPainter(
                testProfile: testProfile,
                controlProfile: controlProfile,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _legendDot(Colors.blue, 'Test Line'),
            const SizedBox(width: 16),
            _legendDot(Colors.green, 'Control Line'),
          ],
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.black87),
        ),
      ],
    );
  }
}

class _ProfileGraphPainter extends CustomPainter {
  final List<double> testProfile;
  final List<double> controlProfile;

  _ProfileGraphPainter({
    required this.testProfile,
    required this.controlProfile,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFF8F9FA),
    );

    final allValues = [...testProfile, ...controlProfile];
    if (allValues.isEmpty) return;
    final double sharedMax = math.max(allValues.reduce(math.max), 1e-9);

    const leftPadding = 28.0;
    const rightPadding = 12.0;
    const topPadding = 16.0;
    const bottomPadding = 24.0;
    final chartWidth = size.width - leftPadding - rightPadding;
    final chartHeight = size.height - topPadding - bottomPadding;
    final bottom = size.height - bottomPadding;

    final axisPaint = Paint()
      ..color = Colors.black12
      ..strokeWidth = 1;
    final gridPaint = Paint()
      ..color = Colors.black12
      ..strokeWidth = 0.5;

    const gridLines = 4;
    for (var i = 0; i <= gridLines; i++) {
      final y = topPadding + chartHeight * i / gridLines;
      canvas.drawLine(
        Offset(leftPadding, y),
        Offset(size.width - rightPadding, y),
        gridPaint,
      );
    }
    canvas.drawLine(
      const Offset(leftPadding, topPadding),
      Offset(leftPadding, bottom),
      axisPaint,
    );
    canvas.drawLine(
      Offset(leftPadding, bottom),
      Offset(size.width - rightPadding, bottom),
      axisPaint,
    );

    void drawProfile(List<double> values, Color color) {
      if (values.length < 2) return;
      final path = Path();
      final step = chartWidth / (values.length - 1);
      for (var i = 0; i < values.length; i++) {
        final x = leftPadding + step * i;
        final y = bottom - (values[i] / sharedMax) * chartHeight;
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round,
      );
    }

    drawProfile(controlProfile, Colors.green.shade700);
    drawProfile(testProfile, Colors.blue.shade700);

    // Y axis is relative to the stronger line (1.00 = its peak).
    const labelStyle = TextStyle(color: Colors.black54, fontSize: 10);
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i <= gridLines; i++) {
      final labelValue = 1.0 - i / gridLines;
      textPainter.text = TextSpan(
        text: labelValue.toStringAsFixed(2),
        style: labelStyle,
      );
      textPainter.layout(minWidth: 0, maxWidth: leftPadding - 4);
      final y =
          topPadding + chartHeight * i / gridLines - textPainter.height / 2;
      textPainter.paint(canvas, Offset(0, y));
    }
  }

  @override
  bool shouldRepaint(covariant _ProfileGraphPainter oldDelegate) =>
      oldDelegate.testProfile != testProfile ||
      oldDelegate.controlProfile != controlProfile;
}
