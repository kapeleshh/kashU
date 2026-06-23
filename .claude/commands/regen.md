---
description: Run the canonical pre-commit loop — build_runner → analyze → test
allowed-tools: Bash
---

Run KashU's mandatory verification loop in order, stopping at the first failure
and reporting exactly what broke:

1. **Generate code** — `dart run build_runner build --delete-conflicting-outputs`
   (regenerates Hive/Riverpod `*.g.dart`; required after any model change).
2. **Lint + type check** — `flutter analyze --fatal-infos` (the CI gate; infos fail).
3. **Tests** — `flutter test`. If `$ARGUMENTS` is given, pass it through
   (e.g. a file path or `--name "..."`) to run a single test instead of the suite.

Report a concise pass/fail summary per step. If a step fails, show the relevant
output and stop — do not continue to the next step.
