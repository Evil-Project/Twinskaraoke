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
5. Push the branch and open the PR with `gh pr create`, filling in every
   section of `.github/pull_request_template.md`. Link issue $ARGUMENTS with
   "Closes #…". Under "AI assistance" name the tool used. Tick only the
   checklist items that are actually true.
6. Print the PR URL.
