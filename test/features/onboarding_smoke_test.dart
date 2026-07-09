import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kashu/features/onboarding/onboarding_screen.dart';

/// Smoke test: the onboarding flow builds and its three pages render with the
/// current copy (guards the #37 wording changes). Stops short of "Get Started",
/// which navigates into the provider/Hive-backed dashboard.
void main() {
  Future<void> pumpOnboarding(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0; // comfortable 540×1200 logical viewport
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> swipeToNextPage(WidgetTester tester) async {
    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('renders and pages through the three onboarding screens',
      (tester) async {
    await pumpOnboarding(tester);

    // Page 1
    expect(find.text('Welcome to KashU'), findsOneWidget);
    expect(find.text('All your investments, one calm dashboard.'),
        findsOneWidget);

    // Page 2 — benefit-focused feature subtitles (no vendor trivia).
    await swipeToNextPage(tester);
    expect(find.text('Everything in one place'), findsOneWidget);
    expect(find.text('Live prices for NSE, BSE and NASDAQ'), findsOneWidget);
    expect(find.textContaining('Yahoo Finance'), findsNothing);

    // Page 3 — single privacy claim + Get Started CTA.
    await swipeToNextPage(tester);
    expect(find.text('Your data stays on your device'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
  });
}
