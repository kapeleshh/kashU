#!/usr/bin/env bash
# PostToolUse hook — regenerate Hive/Riverpod *.g.dart when a model changes.
#
# CLAUDE.md rule: "Code generation is mandatory before analyze/test/run." Editing
# a @HiveType/@HiveField model without rerunning build_runner breaks the build
# with missing-symbol errors. This runs build_runner automatically so that never
# slips through. Only fires for hand-written files under lib/data/models/.
set -uo pipefail

input=$(cat)

file=$(printf '%s' "$input" | python3 -c \
  'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))' \
  2>/dev/null || true)

# Only care about hand-written model sources, not generated *.g.dart.
case "$file" in
  *lib/data/models/*.g.dart) exit 0 ;;
  *lib/data/models/*.dart) ;;
  *) exit 0 ;;
esac

# Locate dart: PATH first, then common local install locations.
DART=""
if command -v dart >/dev/null 2>&1; then DART="dart"
elif [ -x "$HOME/development/flutter/bin/dart" ]; then DART="$HOME/development/flutter/bin/dart"
elif [ -x "$HOME/fvm/default/bin/dart" ]; then DART="$HOME/fvm/default/bin/dart"
else
  echo "regen hook: dart not found on PATH — skipping build_runner. Run it manually." >&2
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

echo "Model changed ($file) — running build_runner to refresh *.g.dart…" >&2
if ! "$DART" run build_runner build --delete-conflicting-outputs >&2 2>&1; then
  # Exit 2 feeds stderr back to Claude so it fixes the annotations.
  echo "build_runner FAILED — *.g.dart is stale. Fix the @HiveType/@HiveField annotations." >&2
  exit 2
fi
exit 0
