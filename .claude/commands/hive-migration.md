---
description: Add or change a Hive @HiveField safely — bump schema version + migration step
allowed-tools: Bash, Read, Edit, Glob, Grep
---

Guide a Hive model change end-to-end so it can't corrupt users' encrypted local
data. The change to make: $ARGUMENTS

Follow this sequence exactly — it encodes the rules in
`lib/data/migration/hive_migration_service.dart` and CLAUDE.md:

1. **Edit the model** under `lib/data/models/`. When adding a field, give it the
   **next unused `@HiveField` number** — NEVER reuse or reorder existing field
   numbers, and never change a model's fixed `typeId` (AssetType=0, Asset=2, …).
   New fields must be nullable or have a default (old records won't have them).

2. **Bump the schema version.** In `hive_migration_service.dart`, increment
   `_currentSchemaVersion` by one.

3. **Add the migration step.** Add an entry to the `_migrations` map keyed by the
   new version number. Pure additive `@HiveField`s need only a no-op (Hive returns
   null/default for missing fields). For data *transforms*, iterate the box values
   and rewrite them in the step.

4. **Regenerate adapters** — `dart run build_runner build --delete-conflicting-outputs`.

5. **Verify** — `flutter analyze --fatal-infos` then `flutter test`. Add or update a
   test under `test/` covering the migration if it transforms data.

Before finishing, state: the field number used, old → new schema version, and
whether the migration is a no-op or a data transform. Flag any reused field number
or `typeId` change as a blocking error.
