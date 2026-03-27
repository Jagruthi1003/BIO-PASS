import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bio_pass/main.dart';

void main() {
  testWidgets('MyApp renders', (tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
