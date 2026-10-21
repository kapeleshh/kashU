import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kashu/features/startup/database_error_app.dart';

void main() {
  late int retries;
  late int resets;

  setUp(() {
    retries = 0;
    resets = 0;
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    DatabaseErrorKind kind = DatabaseErrorKind.keyUnavailable,
    Future<void> Function()? onReset,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: DatabaseErrorScreen(
        kind: kind,
        detail: 'key missing',
        onRetry: () => retries++,
        onReset: onReset ?? () async => resets++,
      ),
    ));
  }

  testWidgets('explains a key problem as a restore onto another device',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text("KashU can't unlock your data"), findsOneWidget);
    expect(find.textContaining('restoring a phone backup'), findsOneWidget);
    expect(find.textContaining('Import Data'), findsOneWidget);
    expect(find.text('key missing'), findsOneWidget);
  });

  testWidgets('"Try again" re-runs startup', (tester) async {
    await pumpScreen(tester, kind: DatabaseErrorKind.openFailed);

    expect(find.text('Unable to open database'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retries, 1);
    expect(resets, 0);
  });

  testWidgets('reset needs an in-page confirmation, and cancel backs out',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Reset KashU…'));
    await tester.pump();
    expect(find.text('Delete all KashU data on this device?'), findsOneWidget);
    expect(resets, 0, reason: 'opening the confirmation deletes nothing');

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(find.text('Delete all KashU data on this device?'), findsNothing);
    expect(resets, 0);
  });

  testWidgets('confirming runs the reset', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Reset KashU…'));
    await tester.pump();
    await tester.tap(find.text('Delete and reset'));
    await tester.pump();

    expect(resets, 1);
  });

  testWidgets('a failed reset says so instead of failing silently',
      (tester) async {
    await pumpScreen(tester,
        onReset: () async => throw StateError('disk busy'));

    await tester.tap(find.text('Reset KashU…'));
    await tester.pump();
    await tester.tap(find.text('Delete and reset'));
    await tester.pump();

    expect(find.textContaining('The reset did not finish'), findsOneWidget);
    expect(find.textContaining('disk busy'), findsNothing);
  });
}
