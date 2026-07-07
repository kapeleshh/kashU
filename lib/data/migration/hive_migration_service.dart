import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../core/constants/app_constants.dart';

/// Current schema version. Increment this when adding new Hive fields or
/// changing existing model structure. Each increment must have a corresponding
/// migration step in [_migrations].
///
/// This is the *Hive on-disk* schema version. It is independent of the
/// backup/export JSON format version (`AppConstants.backupFormatVersion`,
/// enforced by ImportValidator) — the two just happen to be numbered
/// similarly and evolve on their own schedules.
const int _currentSchemaVersion = 1;

/// A single migration step: transforms box data from one version to the next.
typedef _Migration = Future<void> Function(Box settings);

/// Manages Hive schema migrations to prevent data corruption when models change.
///
/// How it works:
/// 1. On each app start (after boxes are opened), call [runMigrations].
/// 2. The service reads the stored schema version from settings.
/// 3. Any migrations with a version > stored version are run in order.
/// 4. The stored version is updated to [_currentSchemaVersion].
///
/// How to add a migration (example: adding a new field to Asset):
/// ```dart
/// const int _currentSchemaVersion = 2; // ← bump this
///
/// static const _migrations = <int, _Migration>{
///   1: _baseline,
///   2: _addAssetTagField, // ← add new entry
/// };
///
/// static Future<void> _addAssetTagField(Box settings) async {
///   // Hive handles missing fields gracefully for new HiveField additions
///   // (they'll be null / their default value). For data transforms,
///   // iterate Hive.box<Asset>(...).values and rewrite.
/// }
/// ```
abstract final class HiveMigrationService {
  /// Map of schema version → migration step to reach that version.
  static const Map<int, _Migration> _migrations = {
    1: _baseline, // V1 is the initial schema — no transforms needed
  };

  /// Run any pending migrations. Call this after all Hive boxes are opened.
  static Future<void> runMigrations() async {
    final settings = Hive.box(AppConstants.settingsBox);
    final storedVersion =
        settings.get(AppConstants.keySchemaVersion, defaultValue: 0) as int;

    if (storedVersion >= _currentSchemaVersion) return; // nothing to do

    for (int v = storedVersion + 1; v <= _currentSchemaVersion; v++) {
      final migration = _migrations[v];
      if (migration == null) continue;
      try {
        await migration(settings);
      } catch (e, stack) {
        debugPrint('[KashU] Migration v$v failed — will retry next launch: $e\n$stack');
        // Stop here; do NOT advance the stored version so the migration retries.
        return;
      }
      // Persist progress after each step so a crash mid-sequence doesn't
      // force a full re-run from the beginning.
      await settings.put(AppConstants.keySchemaVersion, v);
    }
  }

  // ─── Migration steps ───────────────────────────────────────────────────

  /// V1 baseline — the schema that existed at first public release.
  /// No data transforms required; just records the version.
  static Future<void> _baseline(Box _) async {
    // No-op: existing boxes are already in V1 shape.
  }
}
