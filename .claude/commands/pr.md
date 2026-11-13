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
   commented-out code, unlocalized strings, TODOs without an issue. If the
   diff has SwiftUI code, run the `swiftui-pro` skill's review process over
   it: fix what it finds in lines you touched, and note findings in code you
   didn't change for the PR description instead of fixing them. If that
   changes code, run `Scripts/verify.sh` again.
5. Build the description from the team template, following "Pull requests"
   in `AGENTS.md`: create a body file with
   `mktemp "${TMPDIR:-/tmp}/pr-body.XXXXXX"`, copy
   `.github/pull_request_template.md` into it, fill in every section (link
   issue $ARGUMENTS with "Closes #…", tick only checklist items that are
   true). Under "AI assistance" name the AI tool, then either say that
   `swiftui-pro` was applied and list the skill rules you didn't follow, each
   with its reason, or write "No SwiftUI changes." Show the body to me before
   opening the PR. Use that same file in steps 6 and 7.
6. Push the branch and open the PR with
   `gh pr create --base <parent branch if stacked, else main> --title "…" --body-file <body file>`.
   Don't use `--fill` or `--body`: they skip the template.
7. Check the opened PR's description (`gh pr view --json body`) matches the
   filled-in template, then print the PR URL.
