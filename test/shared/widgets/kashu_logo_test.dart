import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kashu/core/constants/app_colors.dart';
import 'package:kashu/core/constants/brand_mark.dart';
import 'package:kashu/core/theme/app_theme.dart';
import 'package:kashu/shared/widgets/kashu_logo.dart';

/// Points along the cashew's outline, in the 100 × 100 design space.
List<Offset> outline() => [
      for (final metric in BrandMark.nutPath().computeMetrics())
        for (var d = 0.0; d <= metric.length; d += 0.5)
          metric.getTangentForOffset(d)!.position,
    ];

void main() {
  group('BrandMark geometry', () {
    test('the cashew and coin sit inside the tile', () {
      for (final p in outline()) {
        expect(p.dx, inInclusiveRange(0, 100));
        expect(p.dy, inInclusiveRange(0, 100));
      }
      final c = BrandMark.coinCenter;
      final r = BrandMark.coinRadius;
      expect(c.dx - r >= 0 && c.dx + r <= 100, isTrue);
      expect(c.dy - r >= 0 && c.dy + r <= 100, isTrue);
    });

    // The launcher icon maps the 100-unit tile onto the 72dp a mask leaves
    // visible; Android only guarantees the central 66dp circle survives
    // every mask shape.
    test('everything fits the adaptive icon safe zone', () {
      const safeRadius = 33 / 72 * 100;
      const centre = Offset(50, 50);
      for (final p in outline()) {
        expect((p - centre).distance, lessThanOrEqualTo(safeRadius));
      }
      final coinFar = (BrandMark.coinCenter - centre).distance +
          BrandMark.coinRadius;
      expect(coinFar, lessThanOrEqualTo(safeRadius));
    });

    test("the wordmark's U box takes in the whole coin", () {
      final box = BrandMark.glyphBox;
      final c = BrandMark.coinCenter;
      final r = BrandMark.coinRadius;
      expect(box.top, lessThanOrEqualTo(c.dy - r));
      expect(box.left, lessThanOrEqualTo(c.dx - r));
      expect(box.right, greaterThanOrEqualTo(c.dx + r));
    });

    test('the coin reads against both the cashew and the tile', () {
      // The gold must stand apart from the cream cashew it sits in and the
      // lavender behind it, or the mark turns into a blob at 20 px.
      double contrast(Color a, Color b) {
        final la = a.computeLuminance(), lb = b.computeLuminance();
        return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
      }

      expect(contrast(BrandMark.nut, BrandMark.tile), greaterThan(3));
      expect(contrast(BrandMark.coin, BrandMark.tile), greaterThan(2));
    });
  });

  Future<void> pump(WidgetTester tester, Widget child, Brightness b) =>
      tester.pumpWidget(MaterialApp(
        theme: b == Brightness.dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        home: Scaffold(body: Center(child: child)),
      ));

  testWidgets('KashuMark is a labelled image at the requested size',
      (tester) async {
    await pump(tester, const KashuMark(size: 88, glow: true), Brightness.light);

    expect(tester.getSize(find.byType(KashuMark)), const Size(88, 88));
    expect(find.bySemanticsLabel('KashU logo'), findsOneWidget);
  });

  Color kashColour(WidgetTester tester) {
    final text = tester.widget<RichText>(find.descendant(
        of: find.byType(KashuWordmark), matching: find.byType(RichText)));
    // Text.rich wraps the span in one carrying the default style; find ours.
    TextSpan? kash;
    text.text.visitChildren((span) {
      if (span is TextSpan && span.text == 'Kash') kash = span;
      return kash == null;
    });
    return kash!.style!.color!;
  }

  testWidgets('KashuWordmark reads as "KashU" in deep ink on light',
      (tester) async {
    await pump(tester, const KashuWordmark(fontSize: 28), Brightness.light);

    expect(find.bySemanticsLabel('KashU'), findsOneWidget);
    expect(kashColour(tester), AppColors.brandInk);
  });

  testWidgets('KashuWordmark turns cream on dark', (tester) async {
    await pump(tester, const KashuWordmark(fontSize: 28), Brightness.dark);

    expect(kashColour(tester), AppColors.brandCream);
  });
}
