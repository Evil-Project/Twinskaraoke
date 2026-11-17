# Upstream and local changes

This skill is a **repo-owned fork**. It was copied from upstream and then
corrected here, so it is no longer pinned in `skills-lock.json` and
`npx skills update` does not touch it. Fix mistakes directly in this folder,
add them to the list below, and consider sending the fix upstream.

To pull in upstream changes later, diff upstream against the commit below and
re-apply each change in the list on top.

- **Source:** https://github.com/AvdLee/Swift-Testing-Agent-Skill
- **Path upstream:** `swift-testing-expert`
- **Forked from commit:** `798e9b1` (2026-11-17)
- **License:** MIT, copy in `LICENSE` next to this file

## Local changes

The changes fix example code and claims flagged in review (CodeRabbit, PR #273)
and verified against the Swift/Apple SDKs and library sources.

- `SKILL.md` and `migration-from-xctest.md`: migrate one test at a time, converting its assertions together with the test; never leave `#expect` inside an XCTest method.
- `migration-from-xctest.md` and `async-testing-and-waiting.md`: confirmation examples confirm from an event handler and await the work inside the block.
- `expectations.md`: the `withKnownIssue` example exercises the affected call.
- `performance-and-best-practices.md`: `init` runs once per test; shared read-only fixtures use `static let`; reset isn't isolation.
- `parallelization-and-isolation.md`: resetting a shared singleton isn't isolation.
- `parameterized-testing.md`: per-argument reruns need an encodable identity (`Feature` gets a `String` raw value); the `InlineArray` `zip` example compiles (no `Sequence` conformance, literal initialisation).
- `traits-and-tags.md`: `.timeLimit` uses `.minutes`, the only unit it has.
