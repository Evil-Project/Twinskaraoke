# Splash walkthrough maintenance

This is an interactive iPhone/iPad root gate, separate from the OS launch screen.
The other platform and widget targets do not use it.

## Open Studio

Open Account → About. Tap the version row **20 times** (dismiss the existing
Easter Egg after tap 10), then return to Account → Settings → Developer →
**Splash Screen Studio**. The existing unlock also works in release
builds. Studio is available only while DeveloperMode.isEnabled.

Choose Install or Update. Studio starts with the bundled content, or your saved
local draft if one exists. Tap a slide to edit its stable ID, optional title/body,
image or SF Symbol, image accessibility description, colors, layout, text
alignment and typography. Select an image from Photos or **Import Image from Files**; resize/compress it with
the dimension and JPEG quality controls. Images are embedded in the JSON.

Add slides with Add Slide. Swipe right or use the context menu to duplicate;
use Edit to delete and drag to reorder. At least one slide must remain.
Edit Next and final button labels in the main form. Save Local Draft stores an
installation-local draft independently of runtime completion state. Switching
modes saves the current valid draft; backgrounding or leaving Studio also saves.
Load Bundled Content explicitly replaces the current draft after confirmation.
Import JSON validates a prior export for the selected mode. Preview uses the
runtime renderer with a separate Exit Preview control. Preview never changes
runtime progress or completion. Export uses the system file exporter; cancellation
leaves the draft intact. Success is reported only by a successful exporter result.

In Developer, **Always Show Splash** offers Off / Install / Update. When enabled,
the selected content appears on each foreground opening, including disabled
updates for testing. Testing runs use separate persisted progress under
`SplashExperience/DeveloperTesting` and never change real completion history.
Interrupted tests resume; completed tests restart at slide one on the next
foreground opening. Turn it Off to restore normal eligibility. Disabling Developer
mode also switches it Off. Real pending walkthroughs still finish before a forced
test run, and the test gate uses the same mandatory renderer and controls.

## Exact canonical source files

- `Twinskaraoke/Resources/SplashScreens/install.json`
- `Twinskaraoke/Resources/SplashScreens/update.json`

Replace the corresponding file with the exported JSON, retain its filename, and
build a new release. Export cannot modify the bundle of an installed app. No Swift
code edits are needed for content replacement. Xcode synchronized groups currently
copy these JSON files to the bundle root; the loader also supports preserved
`SplashScreens` and `Resources/SplashScreens` folders. Verify both files in the
built app after changing resource/project configuration.

## Prepare an announcement

Choose Update → New Announcement to generate a fresh unique ID. Ordinary edits
must preserve an existing announcement ID. Turn on **Show Update Walkthrough for
This Release**, set target marketing version to the release's
`CFBundleShortVersionString`, and optionally set target
build to `CFBundleVersion`. Build matching is exact when supplied. Edit and preview
slides, export `update.json`, replace its canonical source file, then build and ship.
Reusing an announcement across builds does not replay it for people who completed
that ID. Completion IDs survive updates and downgrades. Only the currently bundled,
enabled, matching announcement is considered; no missed-release backlog is shown.
For an ordinary update, leave **Show Update Walkthrough for This Release** off,
export the disabled `update.json`, replace its source file, then rebuild. The
shipped update is disabled with two placeholder slides; install has three
placeholder slides.

Install comes first when both are pending, then Update, before the app opens.
Next and Back are the only runtime navigation. Progress is noninteractive; there
is no skip or dismiss action. Every slide must be visited in sequence. Progress
and completion are persisted atomically before advancing/unlocking. If content
changes while unfinished, its fingerprint no longer matches and progress restarts
at slide one. Completed install onboarding is independent of content/ID/version
and stays completed when install content changes. Malformed install content uses
three built-in placeholder slides; malformed update content is logged and skipped
without recording completion.

## State and reinstall semantics

Private `Library/Application Support/SplashExperience/state.json` contains schema
version, install completion, completed announcement IDs and pending progress with
content fingerprint. The directory/file are excluded from backup (reapplied after
writes). State is outside account data, Keychain, app groups, iCloud, caches and
ordinary cache clearing. Missing state means onboarding is pending for both new
and existing installations when this feature first ships. Unreadable/protected,
corrupt or unsupported state blocks with Retry; it never silently becomes a fresh
installation. Foreground/protected-data availability also retry failures.

Deleting the app deletes this installation-local state and onboarding returns on
reinstallation. Offload/reinstall retaining app data is the same installation.
Backup restores and device migration can affect retained state; this is not perfect
detection of every redownload. Signing in/out, switching accounts, normal updates,
cache clearing and editing welcome content do not reset completion.

## Format and limits

Schema 1 is shared by the loader, Studio, preview, importer and exporter. JSON has
`schemaVersion`, `kind` (`install`/`update`), stable `id`, `enabled`, optional
`targetVersion`/`targetBuild`, `nextLabel`, `finalLabel` and ordered `slides`.
Install must be enabled and cannot have release targets. Slide fields are `id`,
optional `title`, `body`, `symbol`, `imageData` (base64), `imageDescription`,
`backgroundColor`, `textColor`, `layout`, `alignment`, `typography`.
Layouts: `imageAbove`, `textAbove`, `textOnly`. Alignment: `leading`, `center`,
`trailing` (logical direction, including RTL). Typography: `standard`, `large`,
`compact`, all scaled with Dynamic Type. Colors use `#RRGGBB`.

IDs use 1–128 ASCII letters/digits/dots/underscores/hyphens; slide IDs must be
unique. Limits: 1–30 slides, title 300 characters, body 12000, button labels 60,
image descriptions 1000, JSON 12 MB, each image 2 MB/4096 × 4096 pixels. Images
must be valid still images with an accessibility description; a slide may have an
image or a valid SF Symbol. Studio downsamples to 256–2048 pixels and JPEG-compresses
selected images. Content is native structured data with no scripts, HTML, remote
assets or absolute screen coordinates.

## Tests

Existing `-UITestMode` launches bypass the gate only in DEBUG builds. Dedicated
splash UI tests add `-UITestSplash` to exercise the actual root renderer/coordinator
using an isolated `SplashExperience/UITest` state directory. `-UITestSplashReset`
resets only that test directory, and `-UITestSplashUpdate` supplies a matching test
announcement. These flags cannot bypass onboarding in a release build.

## Slide design and app demonstrations

Title and body each offer 12–72 point sizes, system/rounded/serif/monospaced fonts,
and regular/medium/semibold/bold weights. Sizes follow Dynamic Type. Vertical
Content Alignment places the flowing content at the top, center or bottom.
Images have adjustable width and 0–80 point rounded corners. Files imports use
the system picker, read at most 30 MB, and embed the resized image; they do not
retain a dependency on the original file. Mock artwork supports Photos and Files too.

**Preview This Slide** shows one slide with the runtime renderer. **Arrange on
Canvas** uses the full available screen for direct selection and dragging. **Edit Selected Item** opens a separate panel with editable
text and normalized horizontal/vertical/width controls. Center Horizontally and
Center Vertically set the selected item's position to 50%. Freeform positions
adapt to the available screen; tall content remains scrollable. Layout positions
can overlap intentionally, so check the finished design on phone and tablet and
with larger text. Turning Freeform Positions off restores flowing layout.

Add App Feature creates customizable demo copies of existing song rows, mini
player, album cards, play/pause and favorite buttons, search, tabs, settings toggles,
volume and lyrics. Customize labels, initial values, artwork, colors, fonts,
corners and highlights. These controls keep local demonstration state; they do
not call the real player, modify favorites/settings, or navigate the real app.
Interaction Slideshow supports 1–12 steps, each with 1–12 controls, titles and
captions. Controls inside a step flow in their configured order; the whole
slideshow can be positioned on the slide canvas. Steps can advance using their demo navigation or automatically after
an interaction. Demo progress never advances or dismisses the outer walkthrough.

Save Local Draft provides haptic feedback and a floating, dismissible status
bubble at the top. Success is announced to VoiceOver and disappears after eight
seconds. Automatic background saves do not show a success bubble.

Schema 1 retains compatibility with original exports. Optional slide fields
`design`, `features` and `demonstration` hold the new typed definitions; missing
fields use the original layout and typography. Invalid styles, positions, demo
steps or embedded artwork are rejected before saving/exporting. Designs and
controls are included in the content fingerprint.

Debug UI tests can use `-UITestSplashStudio` for an isolated editor and
`-UITestSplashStudioReset` to reset only its test drafts. The debug host exports
a generated PNG to exercise Files import. `-UITestSplashDesign` supplies local
interactive fixtures for dedicated root-gate tests. None of these hosts or flags
are available in Release.

## Canvas grid, resizing, backgrounds and assets

The canvas toolbar's grid button toggles **Snap to Grid**. Guides appear only
while editing, and positions/box dimensions snap to 5% steps when a gesture ends.
Turning the grid on aligns existing items once; turning it off preserves them.
Pinch an item to expand/contract its box, or pull the selected item's lower-right
corner. Width remains 20–100%; optional minimum height remains 5–150% of the
available canvas. Content stays readable rather than being clipped to a small
box. The panel also offers width/height sliders and **Fit Box Height to Content**;
VoiceOver actions offer Expand/Contract Box as an alternative to gestures.

**Choose Bundled Asset** is available for slide images and mock-control artwork.
The gallery includes the app logo, wide branding banner, and branding background,
copied from the existing branding files. It contains no README screenshots or
Shimeji artwork. Selected bytes are embedded in exported JSON, including PNG
transparency, so exports never depend on asset names. Existing Photos and Files
imports remain available. JPEG recompression does not preserve transparency.

Each slide's **Background Image** section accepts Photos, Files, or **Choose
Background Asset**. Fit/Fill controls cropping, and 0–90% black dimming helps keep
text readable. The color background remains behind the image. Removing the image
restores the color. Backgrounds are decorative and are excluded from VoiceOver
focus; their description is stored in the JSON.

## Proposed install walkthrough

`Twinskaraoke/Resources/SplashScreens/install-proposed.json` is a separate,
self-contained eight-slide proposal. In Install mode choose **Load Proposed
Install Walkthrough**, confirm replacing the local draft, and preview or edit it.
It covers browsing/search, playback/lyrics, favorites/downloads, Home Screen
widgets, the watchOS companion (marked as in development), and thanks to Soul,
the app maintainers, and the community contributors named in the repository's
`README.md`. That README is the source for the proposal's contributor list.
No README screenshots or Shimeji artwork are used. The proposal uses branding,
SF Symbols, and local interactive mock controls.

The live `install.json` remains the three-slide placeholder. To adopt the
proposal, export it as `install.json`, replace the canonical file, and rebuild.
Completed installations remain completed even after that replacement.

## Reset one splash and close the app

Developer offers **Reset Install Splash & Close App** and **Reset Update Splash
& Close App**, each with confirmation. Install reset clears only install
completion/progress. Update reset clears completion of the currently bundled
announcement and update progress, retaining completion of other announcement
IDs. Both use the real installation-local state, turn Always Show Splash off,
and close the app only after a successful atomic save. Read/write failures show
an error and keep the app open. Reopen the app to exercise ordinary eligibility.
A disabled or nonmatching update still does not appear after a reset.
Login, credentials, account data, caches, and drafts are not cleared. This is an
explicit hidden Developer action, available in developer-enabled release builds.
