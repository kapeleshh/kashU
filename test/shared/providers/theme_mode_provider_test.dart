import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:kashu/core/constants/app_constants.dart';
import 'package:kashu/shared/providers/settings_providers.dart';

void main() {
  group('themeModeFromStored', () {
    test('reads each saved choice back', () {
      expect(themeModeFromStored('system'), ThemeMode.system);
      expect(themeModeFromStored('light'), ThemeMode.light);
      expect(themeModeFromStored('dark'), ThemeMode.dark);
    });

    test('anything else means System', () {
      for (final junk in [null, '', 'Dark', 'night', 1, true]) {
        expect(themeModeFromStored(junk), ThemeMode.system, reason: '$junk');
      }
    });
  });

  group('themeModeProvider', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('kashu_theme_mode_test');
      Hive.init(tempDir.path);
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await tempDir.delete(recursive: true);
    });

    test('defaults to System on a fresh install', () async {
      await Hive.openBox(AppConstants.settingsBox);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    test('defaults to System when the settings box is not open', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    test('a choice is written to disk and read back after a restart', () async {
      await Hive.openBox(AppConstants.settingsBox);
      final first = ProviderContainer();
      await first.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark);
      expect(first.read(themeModeProvider), ThemeMode.dark);
      first.dispose();

      // Restart: close the box so the next read comes from the file.
      await Hive.box(AppConstants.settingsBox).close();
      await Hive.openBox(AppConstants.settingsBox);
      expect(Hive.box(AppConstants.settingsBox).get(AppConstants.keyThemeMode),
          'dark');

      final second = ProviderContainer();
      addTearDown(second.dispose);
      expect(second.read(themeModeProvider), ThemeMode.dark);
    });
  });
}
