# Upstream and local changes

This skill is a **repo-owned fork**. It was copied from upstream and then
corrected here, so it is no longer pinned in `skills-lock.json` and
`npx skills update` does not touch it. Fix mistakes directly in this folder,
add them to the list below, and consider sending the fix upstream.

To pull in upstream changes later, diff upstream against the commit below and
re-apply each change in the list on top.

- **Source:** https://github.com/AvdLee/Swift-Concurrency-Agent-Skill
- **Path upstream:** `skills/swift-concurrency`
- **Forked from commit:** `3b1580d` (2026-11-17)
- **License:** MIT, copy in `LICENSE` next to this file

## Local changes

The changes fix example code and claims flagged in review (CodeRabbit, PR #273)
and verified against the Swift/Apple SDKs and library sources.

- `SKILL.md`: `async let` and `withTaskGroup` rows now state when children are cancelled (a normal group return waits without cancelling; call `cancelAll()` before an early return).
- `async-await-basics.md`: `async let` error/cancellation semantics corrected (left-to-right awaits; failure doesn't cancel siblings immediately).
- `tasks.md`: timeout wrapper documents that it can't enforce the deadline on work that ignores cancellation.
- `actors.md`: transaction pattern rolls back on error instead of committing in `defer`.
- `threading.md`: `Thread.current` examples use the `Thread.currentThread` wrapper (Swift 6 forbids it in async contexts); `updateUI` made `async`; Swift 6.2 features attributed to Xcode 26, not Xcode 16; serial-queue migration no longer claims actors keep FIFO order.
- `core-data.md`: `loadPersistentStores` resumes once after all stores; `CoreDataStore` exposes an awaited `load()` instead of a fire-and-forget `Task` with `try?`; `perform` is generic over its result; batch delete merges deleted IDs into the view context.
- `async-algorithms.md`: `merge`/`combineLatest`/`zip` use AsyncAlgorithms 1.0's free functions; array merge uses a task group; `throttle` uses `latest:` / a valid `reducing:` closure; producer tasks finish the stream on error and are cancelled on termination; channel examples return the channel types and use `fail(_:)`; lazy `AsyncStream` replaced with `makeStream`; `share()` no longer mapped to `AsyncChannel` (point-to-point).
- `async-sequences.md`: counter advances; setup errors reach `finish(throwing:)`; location monitor stops updates on termination; timer task cancelled on termination.
- `migration.md`: lazy stream replaced with `makeStream`; the "rethink" debounce example really debounces.
- `memory-management.md`: weak-self observation no longer claims to end on deallocation; polling loops exit on cancellation; download manager keys tasks by a per-call ID.
- `observation.md`: `isProcessing` cleared with `defer`; the `withObservationTracking` stream stops re-registering after termination; concurrent increments can't publish a stale value.
- `performance.md`: parallel task-group examples keep input order.
- `testing.md`: async wait awaits the task handle with a time limit; scoped teardown runs on failure; `.serialized` scope vs. `withMainSerialExecutor` explained.
- Not changed: `migration.md`'s typed `NotificationCenter` example. The suggested `post(_:subject:)` requires `Subject: AnyObject`, which `[RecentBuild]` isn't, so the existing `post(_:)` is correct.
