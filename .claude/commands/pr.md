---
description: Check the branch, then open a pull request with the team template
argument-hint: "[issue number]"
---

Prepare and open a pull request for the current branch.

1. Refuse if the current branch is `main`. Run `git status`: if there are
   uncommitted or untracked changes that belong to this work, commit them
   first; if some don't belong, stop and ask. Rebase on `origin/main` if
   behind.
2. Check the size: `git diff --stat origin/main...HEAD`. If over ~400 changed
   lines or mixing concerns (refactor + feature, formatting + logic), stop and
   propose a split instead.
3. Make sure `Scripts/verify.sh` passed in this session; if not, run it.
4. Read the whole diff once more and fix leftovers: debug code, `print`,
   commented-out code, unlocalized strings, TODOs without an issue.
5. Build the description from the team template, following "Pull requests"
   in `AGENTS.md`: copy `.github/pull_request_template.md` to
   `"${TMPDIR:-/tmp}/pr-body.md"`, fill in every section (link issue $ARGUMENTS with
   "Closes #…", name the AI tool under "AI assistance", tick only checklist
   items that are true), and show it to me before opening the PR.
6. Push the branch and open the PR with
   `gh pr create --base main --title "…" --body-file "${TMPDIR:-/tmp}/pr-body.md"`.
   Don't use `--fill` or `--body`: they skip the template.
7. Check the opened PR's description (`gh pr view --json body`) matches the
   filled-in template, then print the PR URL.
