---
description: Read a GitHub issue and the relevant code, then write an implementation plan (no edits)
argument-hint: <issue number or URL>
---

Plan the work for GitHub issue $ARGUMENTS in this repository. Do not edit any
files yet.

1. Read the issue (`gh issue view $ARGUMENTS --comments`). If it has no
   acceptance criteria, list the ones you will assume.
2. Read `AGENTS.md` and any `AGENTS.md` in the folders you will touch.
3. Find and read the relevant code. Note which platform targets are affected
   (`Apple/` folders build into every app).
4. Write the plan:
   - Branch name (`feat/…`, `fix/…`, `refactor/…`)
   - Files to change or add, one line each on why
   - Tests to add or update (bug fix = failing regression test first)
   - Risks: playback, navigation, persistence formats, other platforms
   - Whether it fits in one PR under ~400 changed lines; if not, the PR split
5. Stop and wait for approval.
