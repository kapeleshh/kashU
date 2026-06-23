---
description: Write a structured PR description for the current branch (and open it with gh)
allowed-tools: Bash, Read
---

Draft a pull request for the current branch against `main`, in KashU's style.
Optional focus or overrides: $ARGUMENTS

**Gather context first:**

1. `git branch --show-current`, then the full branch diff vs main:
   `git fetch origin main` then `git log origin/main..HEAD --format='%s'` (commits)
   and `git diff --stat origin/main...HEAD` (files). Read key changed files if the
   intent isn't obvious from the diff.
2. Do NOT assume the latest commit is the whole story — summarize the entire branch.

**Title:** a Conventional-Commit-style one-liner — `type(scope): summary`
(e.g. `feat(crypto): add live INR price search`). Match the dominant change.

**Body — use exactly these sections (drop a section only if truly N/A):**

```markdown
## Summary
1–3 sentences: what this PR does and why it exists.

## Changes
- Bullet per meaningful change, grouped by area (services / data / features / ci).
- Note any new AssetType, price source, Hive schema bump, or migration explicitly.

## Testing
- Commands run: `flutter analyze --fatal-infos`, `flutter test` (+ which suites).
- Manual/browser verification if UI changed (built web + proxy_server.py, etc.).

## Risk & notes
- Data-safety callouts: Hive schema/typeId changes, migration steps, encryption.
- Anything reviewers should scrutinize, follow-ups, or out-of-scope items.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

**Open it:** if the branch is pushed, create the PR with a HEREDOC body:
```
gh pr create --base main --title "<title>" --body "$(cat <<'EOF'
...body...
EOF
)"
```
If the branch isn't pushed yet, show the drafted title + body and ask before
pushing. Never target a branch other than `main` unless the user says so.
