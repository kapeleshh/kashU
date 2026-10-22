import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kashu/core/theme/app_theme.dart';
import 'package:kashu/core/theme/font_licenses.dart';

/// A declared font file from FontManifest.json (built from pubspec `fonts:`).
class _DeclaredFont {
  final String asset;
  final int weight;
  final bool italic;
  const _DeclaredFont(this.asset, this.weight, this.italic);
}

Future<Map<String, List<_DeclaredFont>>> _fontManifest() async {
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json'))
      as List<dynamic>;
  return {
    for (final family in manifest.cast<Map<String, dynamic>>())
      family['family'] as String: [
        for (final font
            in (family['fonts'] as List).cast<Map<String, dynamic>>())
          _DeclaredFont(
            font['asset'] as String,
            (font['weight'] as int?) ?? 400,
            font['style'] == 'italic',
          ),
      ],
  };
}

/// Reads usWeightClass and the italic bit straight out of a TTF's OS/2
/// table, and whether it is still a variable font.
({int weight, bool italic, bool variable}) _readFontFile(ByteData data) {
  final numTables = data.getUint16(4);
  int? os2;
  var variable = false;
  for (var i = 0; i < numTables; i++) {
    final record = 12 + i * 16;
    final tag = String.fromCharCodes(
        data.buffer.asUint8List(data.offsetInBytes + record, 4));
    if (tag == 'OS/2') os2 = data.getUint32(record + 8);
    if (tag == 'fvar') variable = true;
  }
  expect(os2, isNotNull, reason: 'no OS/2 table');
  return (
    weight: data.getUint16(os2! + 4),
    italic: data.getUint16(os2 + 62) & 0x1 == 1,
    variable: variable,
  );
}

/// Records every HttpClient anything tries to create.
class _RecordingHttpOverrides extends HttpOverrides {
  int clientsCreated = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clientsCreated++;
    throw StateError('Fonts must not touch the network');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const families = {AppTheme.headingFontFamily, AppTheme.bodyFontFamily};

  final themes = {
    'light': AppTheme.lightTheme,
    'dark': AppTheme.darkTheme,
  };

  List<TextStyle> themeStyles(ThemeData theme) {
    final t = theme.textTheme;
    return [
      t.displayLarge!,
      t.displayMedium!,
      t.displaySmall!,
      t.headlineLarge!,
      t.headlineMedium!,
      t.headlineSmall!,
      t.titleLarge!,
      t.titleMedium!,
      t.titleSmall!,
      t.bodyLarge!,
      t.bodyMedium!,
      t.bodySmall!,
      t.labelLarge!,
      t.labelMedium!,
      t.labelSmall!,
      theme.appBarTheme.titleTextStyle!,
      theme.dialogTheme.titleTextStyle!,
      theme.snackBarTheme.contentTextStyle!,
    ];
  }

  group('theme typography', () {
    themes.forEach((name, theme) {
      test('$name theme: headings are Quicksand, body is Plus Jakarta Sans',
          () {
        final t = theme.textTheme;
        for (final heading in [
          t.displayLarge,
          t.headlineMedium,
          t.titleLarge,
          theme.appBarTheme.titleTextStyle,
        ]) {
          expect(heading!.fontFamily, 'Quicksand');
        }
        for (final body in [
          t.titleMedium,
          t.bodyLarge,
          t.bodyMedium,
          t.labelSmall,
          theme.snackBarTheme.contentTextStyle,
        ]) {
          expect(body!.fontFamily, 'PlusJakartaSans');
        }
      });

      test('$name theme: every style resolves to a bundled weight', () async {
        final manifest = await _fontManifest();
        for (final style in themeStyles(theme)) {
          expect(families, contains(style.fontFamily));
          final declared = manifest[style.fontFamily]!;
          expect(
            declared.any((f) =>
                f.weight == style.fontWeight!.value &&
                f.italic == (style.fontStyle == FontStyle.italic)),
            isTrue,
            reason: '${style.fontFamily} ${style.fontWeight} is not bundled',
          );
        }
      });
    });

    test('the helpers use the bundled families', () {
      expect(AppTheme.heading(size: 20).fontFamily, 'Quicksand');
      expect(AppTheme.body(size: 14).fontFamily, 'PlusJakartaSans');
    });
  });

  group('bundled font files', () {
    test('pubspec declares every weight and style the app uses', () async {
      final manifest = await _fontManifest();
      Set<String> variants(String family) => {
            for (final f in manifest[family] ?? const <_DeclaredFont>[])
              '${f.weight}${f.italic ? 'i' : ''}',
          };

      // AppTheme.heading() is called with w700 and w800; Quicksand's
      // heaviest master is 700, so 700 serves both.
      expect(variants('Quicksand'), {'700'});
      // AppTheme.body() and the text theme use 500–800; the italic hints
      // under the asset form are 500 italic.
      expect(variants('PlusJakartaSans'), {'500', '500i', '600', '700', '800'});
    });

    test('each file is the static weight and style it is declared as',
        () async {
      final manifest = await _fontManifest();
      for (final family in families) {
        for (final font in manifest[family]!) {
          final data = await rootBundle.load(font.asset);
          final file = _readFontFile(data);
          expect(file.variable, isFalse, reason: '${font.asset} is variable');
          expect(file.weight, font.weight, reason: font.asset);
          expect(file.italic, font.italic, reason: font.asset);

          // And the engine accepts it as a font.
          final loader = FontLoader('verify-${font.asset}')
            ..addFont(Future.value(data));
          await loader.load();
        }
      }
    });
  });

  testWidgets('rendering the themed app never makes an HTTP request',
      (tester) async {
    final overrides = _RecordingHttpOverrides();
    await HttpOverrides.runWithHttpOverrides(
      () async {
        for (final theme in themes.values) {
          await tester.pumpWidget(MaterialApp(
            theme: theme,
            home: Scaffold(
              appBar: AppBar(title: const Text('Portfolio')),
              body: Column(children: [
                Text('₹1,23,456', style: AppTheme.heading(size: 34)),
                Text('Hero',
                    style: AppTheme.heading(size: 30, weight: FontWeight.w800)),
                Text('Label',
                    style: AppTheme.body(size: 12, weight: FontWeight.w800)),
                const Text('Hint',
                    style: TextStyle(fontStyle: FontStyle.italic)),
                Text('Body', style: theme.textTheme.bodyMedium),
              ]),
            ),
          ));
          await tester.pumpAndSettle();
        }
      },
      overrides,
    );
    expect(overrides.clientsCreated, 0);
    expect(tester.takeException(), isNull);
  });

  test('the OFL of each bundled family is registered as a licence', () async {
    LicenseRegistry.reset();
    addTearDown(LicenseRegistry.reset);
    registerFontLicenses();

    final entries = await LicenseRegistry.licenses.toList();
    expect(
      entries.expand((e) => e.packages).toSet(),
      {'Quicksand', 'Plus Jakarta Sans'},
    );
    for (final entry in entries) {
      final text = entry.paragraphs.map((p) => p.text).join('\n');
      expect(text, contains('SIL Open Font License'));
    }
  });
}
