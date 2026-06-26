import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/onboarding/onboarding_screen.dart';

void main() {
  testWidgets('shows intro and fires onDone on Get started', (tester) async {
    var done = false;
    await tester.pumpWidget(MaterialApp(
      home: OnboardingScreen(onDone: () => done = true),
    ));
    expect(find.textContaining('Narrarr'), findsWidgets);
    await tester.tap(find.text('Get started'));
    await tester.pump();
    expect(done, isTrue);
  });
}
