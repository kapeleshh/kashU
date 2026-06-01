---
description: Triage an issue — reproduce, locate the cause, and propose a plan WITHOUT changing code
allowed-tools: mcp__playwright, Bash, Read, Glob, Grep
---

Triage the following issue. Investigate only — do NOT edit code, commit, or open a PR.

$ARGUMENTS

Produce a triage report with these sections:

1. **Reproduction.** Try to reproduce in the browser: build web (`flutter build web`),
   serve it (`python3 proxy_server.py` on http://localhost:8080), and drive it with the
   Playwright MCP. State clearly whether it reproduces, on which flow, and what you saw.
2. **Suspected cause.** Point to the specific files/functions involved (use `file:line`
   references). Note which layer it sits in — `services/` (price/network),
   `data/repositories` (Hive), `features/` (UI), or `shared/providers` (Riverpod state).
3. **Severity & scope.** Is data integrity, the encrypted Hive store, or price accuracy at
   risk? Does it affect all asset types or one? Is it web-only or all platforms?
4. **Proposed fix.** Outline the smallest change that would resolve the root cause, and the
   test you'd add under `test/` to lock it in.
5. **Open questions.** Anything ambiguous that needs the maintainer to clarify.

Keep it concise and evidence-based. If you cannot reproduce it, say so and explain why.
