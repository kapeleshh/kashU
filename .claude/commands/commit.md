---
description: Write a Conventional Commit (type(scope): subject + why-bullets) and commit staged changes
allowed-tools: Bash, Read
---

Create a commit for the current changes in KashU's house style. Optional focus or
overrides from the user: $ARGUMENTS

**Style — Conventional Commits (matches this repo's history):**

- Subject: `type(scope): summary` — imperative mood, lower-case, ≤ 72 chars, no
  trailing period.
- **type**: `feat` · `fix` · `docs` · `ci` · `chore` · `refactor` · `test` · `perf`.
- **scope** (optional but preferred): the area touched. Use a domain/feature scope
  when one fits — `stocks`, `crypto`, `mutual-funds`, `metals`, `deposits`,
  `fd-bond`, `ui`, `auth`, `onboarding`, `dashboard`, `settings`, `migration`,
  `prices` — or a layer (`services`, `data`, `core`). Omit the scope for repo-wide
  changes (`ci:`, `chore:`, `docs:`).
- Body: a blank line, then `- ` bullets describing **what changed and why** (not how).
  Skip the body only for genuinely trivial one-line changes.
- End every commit message with this trailer on its own line:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

**Steps:**

1. Run `git status` and `git diff` (and `git diff --staged`) to see what changed.
   If nothing is staged, stage the relevant files with `git add` (ask first if the
   change spans unrelated concerns — prefer one logical commit, or split into
   several).
2. Pick the single best `type(scope)` for the dominant change. If the diff mixes
   unrelated concerns, propose splitting into multiple commits rather than one vague
   message.
3. Draft the message in the style above.
4. **Branch safety:** if currently on `main`, create a topic branch first
   (`git checkout -b <type>/<short-desc>`) — never commit directly to `main`.
5. Commit with a HEREDOC so the body formats correctly:
   ```
   git commit -m "$(cat <<'EOF'
   feat(crypto): ...

   - ...
   - ...

   Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
   EOF
   )"
   ```
6. Show the resulting `git log -1 --stat`. Do NOT push unless the user asks.
