# Upstream and local changes

This skill is a **repo-owned fork**. It was copied from upstream and then
corrected here, so it is no longer pinned in `skills-lock.json` and
`npx skills update` does not touch it. Fix mistakes directly in this folder,
add them to the list below, and consider sending the fix upstream.

To pull in upstream changes later, diff upstream against the commit below and
re-apply each change in the list on top.

- **Source:** https://github.com/Dimillian/Skills
- **Path upstream:** `swiftui-liquid-glass`
- **Forked from commit:** `05ba982` (2026-11-17)
- **License:** MIT, copy in `LICENSE` next to this file

## Local changes

The changes fix example code and claims flagged in review (CodeRabbit, PR #273)
and verified against the Swift/Apple SDKs and library sources.

- `references/liquid-glass.md`: background extension uses `backgroundExtensionEffect()` on the content; removed `scrollExtensionMode(.underSidebar)`, which isn't in the iOS 26 or 27 SDK.
