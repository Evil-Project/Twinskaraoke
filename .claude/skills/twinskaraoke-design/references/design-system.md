# Design system: tokens, themes, components

The iOS app follows Apple Music's visual language. The tokens are the design:
a raw value next to a token is how the interface drifts.

## Where things live

| What | File |
| --- | --- |
| `AM` type, radius, spacing, layout, shadow tokens; `AMSectionHeader`, `InsetGroupedList`, `trackingWidth(into:)`, `withOptionalAnimation`, `scaledSystemFont` | `Apps/iOS/Components/Shared/AppTheme.swift` |
| Fixed colour tokens (`appGlassFill`, `appDivider`, `appShadow`, placeholders, …) | `Apps/iOS/Components/Shared/AppTheme.swift` (`extension Color`) |
| Theme-driven colours (`appAccent`, `appBackground`, `appGroupedBackground`, `appSecondaryBackground`, `appSheetGradient*`, `appPlayerActionFill`, `appDestructive`) | `Packages/UI/Themes/iOS/AppThemePalette.swift` |
| Accent for watch, TV and Mac | `Packages/UI/DesignSystem/Apple/AppAccent.swift` |
| Glass surfaces (`appGlassBackground(in:)`, `GlassCircle`, `GlassRoundedRect`) | `Apps/iOS/Components/Shared/GlassComponents.swift` |
| Press feedback | `Packages/UI/Components/Apple/PressableButtonStyle.swift` |

`AppTheme.swift` is close to 600 lines. Adding a few tokens is fine; a new
component goes in its own file.

## Type: `AM.Font`

Pick by role:

- Screen and section: `screenTitle` (large title, bold), `sectionHeader`
  (title2 bold, 22pt — *not* `.title`), `groupHeader`, `heroTitle`, `eyebrow`
  (always with `.textCase(.uppercase)` and a secondary colour).
- Tiles: `tileTitle` + `tileCaption` are the **same size** and differ only by
  colour. Don't make the title bigger or bolder; that is what turns a shelf
  into "headlines with footnotes".
- Rows: `rowTitle` / `rowSubtitle`, `rowCompactTitle` / `rowCompactSubtitle`.
- Player: `nowPlayingTitle` / `nowPlayingArtist`, the `*Compact` pair for
  tight layouts, `playerGlyph` for round chrome buttons.
- Small: `badge`, `timecode` (monospaced digits), `chevron` — **chevron
  glyphs only**, never a title.

Deliberately left as system fonts, don't "finish the migration": body and
caption text in empty states, rows of inset-grouped settings lists (they
should read as system Settings), and bold card-overlay titles over artwork.
Roughly 300 raw `.font(` calls remain for these reasons.

A custom size that must still scale: `scaledSystemFont(size:weight:design:relativeTo:)`.

## Radius: `AM.Radius`

thumb 6, popup 6, card 10, tile 10, hero 16, sheet 20. Ramped by element size;
a 44pt thumbnail and a 340pt hero never share a corner.

`AM.Radius.hero` is read by both `ArtworkMorphLayer` (which lerps
`thumb → hero`) and `PlayerArtworkView`. They must keep reading the same
token, or the flying artwork lands on a different shape than the artwork it
becomes. `ArtworkMorphGeometryTests` only catches the two drifting apart, not
a changed value, so look at the morph after changing either radius.

Use `.continuous` rounded rectangles.

## Spacing and layout: `AM.Spacing`, `AM.Layout`

- Spacing ramp: xs 4, s 8, m 12, l 16, xl 20, xxl 28; `screenMargin` 16,
  `shelfSpacing` 20, `sectionHeaderGap` 10 (one value for every shelf and
  grid).
- Wide layouts: `AM.Layout.usesWideCanvas(horizontalSizeClass:availableWidth:)`
  and `usesSidebarCanvas(...)`. Don't write your own width breakpoints; the
  thresholds are tuned for the 13-inch iPad's sidebar and for Mac idiom.
- Shelves: `shelfTileWidth(for:compact:)`, `mediaShelfHeight(tileWidth:labelAllowance:)`.
  A shelf's height is fixed because it lives in a `GeometryReader`, so scale
  `shelfLabelAllowance` with `@ScaledMetric(relativeTo: .subheadline)`. A bare
  constant clips tile titles at accessibility sizes.
- Need a container's width outside a `GeometryReader`: `trackingWidth(into:)`.
  Don't add another width-in-state helper.
- Grids: `AM.Layout.adaptiveGridColumns(minimum:spacing:)` and the
  `playlist/song/categoryGridColumns` presets.

## Shadows

`amShadow(AM.Shadow.card | .heroIdle | .heroPlaying)`. Hero artwork switches
between idle and playing shadows; don't hand-roll a shadow next to them.

## Colour and themes

- Always a `Color.app*` token or a semantic system style (`.primary`,
  `.secondary`, `.tertiary`). No literal colours, no `Color(red:…)` at a call
  site.
- Themes are the `AppearanceMode` cases
  (`Extensions/WidgetExtension/Shared/SharedTheme.swift`): System, Light,
  Dark, plus Neuro, SMOCUS and Evil (palettes from twinskaraoke.com's CSS;
  SMOCUS is the site's `twins` theme) and Nwero (aurora backdrop). They are
  applied live through the `@Observable` `AppThemeStore.shared`. The theme-driven tokens are computed properties, so
  views redraw when the theme changes. Reading a palette value into a
  `static let` or a `nonisolated` constant freezes it at the launch theme.
- `appAccent` is the theme's primary colour: cyan or purple under some
  themes. Anything destructive uses `appDestructive`, which stays red.
- Screen backgrounds: `musicScreenBackground()` or
  `groupedScreenBackground()`, never `Color.appBackground` painted directly
  (the aurora theme needs its own opaque backdrop per screen).
- Settings-style lists: `InsetGroupedList`. `listRowBackground` on a `List`
  never reaches its rows; it must sit on a `Group` inside the list, which is
  what `InsetGroupedList` does.
- Check every new surface under at least the standard theme in light and dark
  plus one website theme.

## Glass

Use `appGlassBackground(in:fallback:)` for cards, panels and pills,
`GlassCircle` for floating round buttons (interactive glass) and
`GlassRoundedRect` for glass plus the card shadow. They handle Reduce
Transparency (opaque fill) and Increase Contrast (edge stroke). A bare
`.glassEffect` skips both. On a sheet under a website theme, pass a
`fallback:` colour, because the default fill equals the sheet colour there.

## Section headers

One component: `AMSectionHeader`. It takes an **already-localized** `String`
(`String(localized: "…")` at the call site) because the same text often also
feeds a destination's `navigationTitle`. Always forward the caller's
`horizontalPadding`: wide layouts pass 0, and a header left on the 16pt
default sits inset from its own cards on iPad.

## Components to reuse before building new ones

`AMSectionHeader`, `InsetGroupedList`, `ToolbarIconButton`,
`ToolbarCapsuleMenu`, `AccountToolbarButton`, `PressableButtonStyle`,
`MarqueeText`, `EqualizerBars`, `PulsingMusicEmptyStateMark`,
`RemoteArtworkImage`, the glass modifiers above. Search
`Apps/iOS/Components/` first.
