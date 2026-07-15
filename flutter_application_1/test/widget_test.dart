// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/main.dart';

void main() {
  testWidgets('Strip Analyzer screen renders with expected UI', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: StripAnalyzerScreen(cameras: [])));
    await tester.pumpAndSettle();

    expect(find.text('Strip Analyzer'), findsOneWidget);
    expect(find.text('Use Camera with Guide'), findsOneWidget);
    expect(find.text('Test Strip Ready for Quantitation'), findsOneWidget);
  });
}
