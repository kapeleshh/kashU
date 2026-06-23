---
description: Reproduce a web bug in the browser, fix it, test it, verify it, and open a PR
allowed-tools: mcp__playwright, Bash, Edit, Write, Read, Glob, Grep
---

Fix the following bug in the KashU Flutter web app, end to end:

$ARGUMENTS

Work through these steps in order and report the outcome of each:

1. **Reproduce.** Build web (`flutter build web`) and serve it (`python3 proxy_server.py`
   serves `build/web` on http://localhost:8080). Use the Playwright MCP to load the app
   and reproduce the reported behavior. If you cannot reproduce it, say so explicitly,
   describe what you observed instead, and stop before changing any code.
2. **Find the root cause.** Trace the behavior to its source. Prefer the smallest change
   that fixes the cause rather than the symptom. Follow `CLAUDE.md` — in particular,
   rerun `dart run build_runner build --delete-conflicting-outputs` after editing anything
   in `lib/data/models/`, and never reuse/reorder Hive field numbers.
3. **Test.** Add or update a test under `test/` (mirroring `lib/`) that fails before the
   fix and passes after. Then run `flutter analyze --fatal-infos` and `flutter test`.
4. **Verify in the browser.** Re-run the Playwright flow and confirm the app now shows the
   corrected behavior. Capture a snapshot/screenshot as evidence.
5. **Deliver.** Commit on a branch, push, and open a PR. The PR description must state: what
   you reproduced, the root cause, the fix, and exactly how you verified it (test + browser).

If any step fails or has to be skipped, report it plainly instead of claiming success.
