# Verifying UI, motion and haptics

How to build and test is in AGENTS.md ("Testing", "Commands"). This file
covers what the simulator can and can't show for design work.

## The simulator lies about glass

Screenshots (`xcrun simctl io … screenshot` and XCUITest's
`app.screenshot()`) don't composite Liquid Glass and much of what is drawn on
it. Missing from captures, though present on device:

- the tab bar and navigation-bar glass buttons (the back chevron);
- glass circles behind floating buttons, which then look like bare icons;
- text on `appGlassBackground` in context-menu preview cards (context-menu
  subtitles capture with a black box);
- a scrolling `MarqueeText` inside the tab bar accessory.

For anything on or under glass, trust the accessibility tree (`isHittable`,
labels, frames, `Disabled`) over pixels. Don't "fix" a layout because of how
a capture looks.

## What only a device can confirm

Say in the PR which of these the change touches and that they need a device
check:

- haptics (no Taptic Engine in the simulator);
- glass rendering and its legibility over artwork;
- anything driven by playing audio (lyrics glow, progress, equalizer while
  playing): on a host without an audio output device (VMs, CI) playback
  never starts in the simulator, and HLS streams may not decode there;
- animation feel, frame rate and ProMotion (timings from an emulated
  simulator mean nothing);
- iOS 27 behaviour when the local Xcode is older than CI's.

## Checks that do work here

- **Run with fixtures:** UI tests launch with `-UITestMode 1` and the other
  `-UITest…` arguments in `Tests/UITests/iOS/TwinskaraokeUITests.swift`;
  reuse them.
- **Accessibility sizes:**
  `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`
  as a launch argument. Fixed-height shelves and rows break first.
- **Themes:** `-nk.appearance light` (or `dark`, `neuro`, `smocus`, `evil`,
  `nwero`). The value is written back to the app's defaults, so the next
  launch without it keeps that theme; set it back explicitly.
- **Comparing visual variants headlessly:** render candidates with
  `ImageRenderer` in a throwaway unit test and compare the images. Judge a
  backdrop over a bright cover by sampling pixels, not by eye. Don't commit
  the throwaway test.
- **Layout bugs:** a temporary `.border(.red)` distinguishes a wrong frame
  from drawing that escapes a correct frame in one screenshot. Remove it
  before committing.
- **Hit targets:** an accessibility frame smaller than 44 pt is often just the
  glyph; tap off-centre within 44 pt before reporting a small target.

## False alarms

Leftover UI-test state on a simulator looks like product bugs (a fixture
setlist with a blank cover in Recently Played, a restored "Widget Test 1"
session). Uninstall the app first when a clean state matters. Home reloads
sections asynchronously and can reset scroll state, so test scroll-driven
behaviour (tab bar minimize) on a stable list such as Library → Artists.
