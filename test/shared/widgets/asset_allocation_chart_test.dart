import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kashu/data/models/asset_type.dart';
import 'package:kashu/shared/widgets/asset_allocation_chart.dart';

/// The allocation map handed to the chart holds base-currency AMOUNTS per
/// type (portfolioSummaryProvider), not percentages — the legend once printed
/// ₹2.5 lakh as "250000%".
void main() {
  group('allocationPercentages', () {
    test('turns amounts into whole-percent shares that sum to 100', () {
      final shares = allocationPercentages({
        AssetType.stock: 250000,
        AssetType.crypto: 100000,
        AssetType.gold: 50000,
      });

      // 62.5 / 25 / 12.5 — the tied half-points go to the larger holding.
      expect(shares, {
        AssetType.stock: 63,
        AssetType.crypto: 25,
        AssetType.gold: 12,
      });
    });

    test('three equal thirds still add up to 100', () {
      final shares = allocationPercentages({
        AssetType.stock: 1,
        AssetType.mutualFund: 1,
        AssetType.gold: 1,
      });

      expect(shares.values.reduce((a, b) => a + b), 100);
      expect(shares.values, everyElement(inInclusiveRange(33, 34)));
    });

    test('drops zero, negative and non-finite amounts', () {
      final shares = allocationPercentages({
        AssetType.stock: 300,
        AssetType.cash: 0,
        AssetType.crypto: -50,
        AssetType.gold: double.nan,
      });

      expect(shares, {AssetType.stock: 100});
    });

    test('an empty or all-zero allocation has no shares', () {
      expect(allocationPercentages({}), isEmpty);
      expect(allocationPercentages({AssetType.stock: 0}), isEmpty);
    });
  });

  group('AssetAllocationChart legend', () {
    Future<void> pumpChart(
        WidgetTester tester, Map<AssetType, double> allocation) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AssetAllocationChart(allocation: allocation, assetCount: 4),
        ),
      ));
    }

    List<String> legendPercentLabels(WidgetTester tester) => tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .where((s) => s.endsWith('%'))
        .toList();

    testWidgets('shows each type\'s share, summing to ~100', (tester) async {
      await pumpChart(tester, {
        AssetType.stock: 250000,
        AssetType.mutualFund: 120000,
        AssetType.crypto: 30000,
        AssetType.gold: 1234.56,
      });

      final labels = legendPercentLabels(tester);
      expect(labels, hasLength(4));
      expect(labels, isNot(contains('250000%')));

      final sum = labels
          .map((l) => int.parse(l.replaceAll(RegExp(r'[<%]'), '')))
          .reduce((a, b) => a + b);
      expect(sum, closeTo(100, 1));
      expect(find.text('62%'), findsOneWidget); // 250000 / 401234.56
    });

    testWidgets('a tiny slice reads <1% rather than 0%', (tester) async {
      await pumpChart(tester, {
        AssetType.stock: 100000,
        AssetType.cash: 10,
      });

      expect(find.text('100%'), findsOneWidget);
      expect(find.text('<1%'), findsOneWidget);
      expect(find.text('0%'), findsNothing);
    });

    testWidgets('a zero total shows the empty state instead of a legend',
        (tester) async {
      await pumpChart(tester, {AssetType.stock: 0, AssetType.gold: 0});

      expect(find.text('No allocation yet'), findsOneWidget);
      expect(legendPercentLabels(tester), isEmpty);
    });
  });
}
