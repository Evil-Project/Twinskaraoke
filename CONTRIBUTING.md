# Contributing to Twinskaraoke

We are a small team and most of us write code with AI assistants (Claude Code,
Codex, Cursor, …). This workflow keeps that fast without letting quality slip.
The rules for agents live in [`AGENTS.md`](AGENTS.md); this file is the human
side.

## The loop

1. **Issue first.** Anything bigger than a one-file fix starts as a GitHub
   issue: the problem, the expected behavior, acceptance criteria, platforms
   affected (iOS / iPadOS / watchOS / tvOS / macOS) and what is out of scope.
   5–15 lines is enough. Comment "I'm on it" before you start, so two people
   don't build the same thing.
2. **Branch** from current `main`: `feat/…`, `fix/…`, `refactor/…`, `chore/…`.
   Never work on `main`, and never open a PR from your fork's `main`. Running
   several agents at once? Use one `git worktree` per task.
3. **Plan before code.** Point your agent at the issue and let it read the
   code and write a plan (files, approach, tests). In Claude Code use plan mode
   or `/plan-issue <number>`. Check the plan — a wrong plan is the cheapest
   place to stop a bad change.
4. **Implement in small commits.** Bugs get a failing regression test first.
   Keep a PR to one concern and under ~400 changed lines; split bigger features
   into stacked PRs.
5. **Verify.** Run `Scripts/verify.sh` (or `/verify` in Claude Code). For UI
   changes, run the app yourself and take screenshots.
6. **Open the PR** with the template filled in (`/pr` in Claude Code). CI must
   be green. If you or your agent open it from the command line, use
   `gh pr create --body-file` with a filled-in copy of
   `.github/pull_request_template.md`; `--fill` and `--body` skip the
   template (details in `AGENTS.md` → "Pull requests").
7. **Review.** The AI review bot comments first; fix or answer every finding.
   Then one teammate approves. Code owners are requested automatically for
   playback, navigation, the Xcode project and CI.
8. **Squash-merge.** `main` must always build: every push to it publishes the
   nightly IPA. If the agent kept getting something wrong, add a rule to
   `AGENTS.md` in the same PR.

## Setup

```sh
brew install swiftformat swiftlint xcbeautify
```

Open `Twinskaraoke.xcodeproj` and see [Build from Source](docs/build-from-source.md)
for signing.

## AI tools

- `AGENTS.md` is the single source of project rules. Claude Code reads it via
  `CLAUDE.md`; Codex and Cursor read it directly. Don't keep private copies.
- Personal notes go in `CLAUDE.local.md` / `AGENTS.local.md` (gitignored).
- Shared Claude Code commands live in `.claude/commands/`. Using another tool?
  The files are plain Markdown — tell your agent "follow
  `.claude/commands/plan-issue.md` for issue #42".
- You own every line you submit, generated or not. Read the whole diff before
  you ask for review.

## Pull request rules

- One concern per PR; refactors and features never share a PR.
- Formatting-only changes go in their own PR.
- Don't change CI, `CODEOWNERS` or `AGENTS.md` as a side effect of other work.
- Screenshots or a recording for every UI change, per affected platform.
