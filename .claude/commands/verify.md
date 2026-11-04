---
description: Run Scripts/verify.sh and fix what fails
argument-hint: "[--quick | --lint]"
---

Run `Scripts/verify.sh $ARGUMENTS` from the repository root.

- If formatting fails, format only the Swift files your branch changed and
  rerun:
  `git diff --name-only --diff-filter=d origin/main... -- '*.swift' | xargs swiftformat`
- If SwiftLint fails, run `swiftlint --fix`, then fix the remaining findings in
  code you changed. Don't add `swiftlint:disable` without a reason in the same
  comment, and never regenerate `.swiftlint-baseline.json` to hide new issues.
- If a build or test fails, find the cause and fix it. Never skip, delete or
  weaken a test to make it pass.
- If you can't run part of it (no Xcode), say exactly which steps did not run.

Finish with a short summary: what passed, what you fixed, what is still failing.
