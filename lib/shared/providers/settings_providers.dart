import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/app_constants.dart';

/// Whether this build can send crash reports at all, i.e. a Sentry DSN was
/// baked in with `--dart-define=SENTRY_DSN=…`. Without one, the Settings
/// opt-in switch would do nothing, so it is not shown.
///
/// [AppConfig] is compile-time constant; this provider is the seam widget
/// tests override to exercise both kinds of build.
final crashReportingAvailableProvider =
    Provider<bool>((ref) => AppConfig.isSentryEnabled);

/// The Settings › Appearance choice: follow the phone (the default), or
/// always light / always dark. `MaterialApp.themeMode` watches it, so a
/// change applies at once — to onboarding and the lock screen too.
final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    // Always open by the time the app runs (_preBootstrap); the guard only
    // spares widget tests that pump the app without it.
    if (!Hive.isBoxOpen(AppConstants.settingsBox)) return ThemeMode.system;
    return themeModeFromStored(
        Hive.box(AppConstants.settingsBox).get(AppConstants.keyThemeMode));
  }

  /// Applies [mode] immediately, then persists it so it survives a restart.
  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await Hive.box(AppConstants.settingsBox)
        .put(AppConstants.keyThemeMode, mode.name);
  }
}

/// Reads the stored setting, a [ThemeMode.name]. Anything else — missing,
/// or a corrupted value — means [ThemeMode.system], the default.
ThemeMode themeModeFromStored(Object? stored) {
  for (final mode in ThemeMode.values) {
    if (mode.name == stored) return mode;
  }
  return ThemeMode.system;
}
