import 'package:afts_reader/screens/strip_analyzer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Home screen shows both ways to start', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: StripAnalyzerScreen(cameras: [])),
    );

    expect(find.text('Welcome to Strip Analyzer'), findsOneWidget);
    expect(find.text('Begin testing procedure'), findsOneWidget);
    expect(find.text('Go straight to analysis'), findsOneWidget);
  });

  testWidgets('Go straight to analysis opens the step 5 guide', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: StripAnalyzerScreen(cameras: [])),
    );
    await tester.tap(find.text('Go straight to analysis'));
    await tester.pump();

    expect(find.text('Step 5: Analyze the strip'), findsOneWidget);
  });
}
