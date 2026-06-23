#!/usr/bin/env bash
# Stop hook — run the CI lint gate before a turn ends, but only when Dart
# changed. Mirrors ci.yml's `flutter analyze --fatal-infos`, so a turn can't
# finish "done" while CI would fail. Skips quietly for non-code turns.
set -uo pipefail

input=$(cat)

# Avoid re-entry: if we already blocked once this turn, let it stop.
active=$(printf '%s' "$input" | python3 -c \
  'import sys,json; print(json.load(sys.stdin).get("stop_hook_active", False))' \
  2>/dev/null || echo False)
[ "$active" = "True" ] && exit 0

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

# Only analyze if there are uncommitted Dart changes (tracked or untracked).
if ! git status --porcelain 2>/dev/null | grep -qE '\.dart"?$'; then
  exit 0
fi

# Locate flutter: PATH first, then common local install locations.
FLUTTER=""
if command -v flutter >/dev/null 2>&1; then FLUTTER="flutter"
elif [ -x "$HOME/development/flutter/bin/flutter" ]; then FLUTTER="$HOME/development/flutter/bin/flutter"
elif [ -x "$HOME/fvm/default/bin/flutter" ]; then FLUTTER="$HOME/fvm/default/bin/flutter"
else
  echo "analyze hook: flutter not found on PATH — skipping. Run 'flutter analyze --fatal-infos' manually." >&2
  exit 0
fi

out=$("$FLUTTER" analyze --fatal-infos 2>&1)
if [ $? -ne 0 ]; then
  # Exit 2 blocks the stop and feeds the reason back to Claude to fix.
  echo "flutter analyze --fatal-infos failed (this is the CI gate). Fix before finishing:" >&2
  printf '%s\n' "$out" | tail -40 >&2
  exit 2
fi
exit 0
