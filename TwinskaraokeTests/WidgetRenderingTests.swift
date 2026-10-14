import SwiftUI
import UIKit
import WidgetKit
import XCTest
@testable import Twinskaraoke

nonisolated final class WidgetRenderingTests: XCTestCase {
    @MainActor func testRenderThemeSizeAndFailureMatrix() throws {
        for mode in AppearanceMode.allCases {
            let theme = SharedThemeDefinition.builtIn(mode)
            for scheme in mode == .system ? [ColorScheme.light, .dark] : [mode.colorScheme ?? .dark] {
                let prefix = "\(mode.rawValue)-\(scheme == .dark ? "dark" : "light")"
                for family in [WidgetFamily.systemSmall, .systemMedium] {
                    try render(AnyView(RadioWidgetView(entry: radio(theme: theme), familyOverride: family)), theme: theme, family: family, scheme: scheme, name: "\(prefix)-radio-\(label(family))")
                    let entry = LibraryEntry(playlists: (1...4).map { PlaylistEntity(WidgetPlaylist(id: "\($0)", name: "My music with a longer playlist title \($0)")) }, theme: theme)
                    try render(AnyView(LibraryWidgetView(entry: entry, familyOverride: family)), theme: theme, family: family, scheme: scheme, name: "\(prefix)-library-\(label(family))")
                }
                for family in [WidgetFamily.systemSmall, .systemMedium, .systemLarge] {
                    var playback = PlaybackWidgetSnapshot(song: WidgetSong(id: "song", title: "Wake Me Up Before You Go-Go", artist: "Wham!"), isPlaying: false, hasPrevious: true, hasNext: true)
                    playback.queue = [WidgetSong(id: "next", title: "The next song", artist: "AURORA")]
                    try render(AnyView(PlaybackWidgetView(snapshot: playback, familyOverride: family)), theme: theme, family: family, scheme: scheme, name: "\(prefix)-playback-\(label(family))")
                }
            }
        }
        var custom = SharedThemeDefinition.builtIn(.neuro)
        custom.id = "custom-amber-no-name-branch"
        custom.dark[.primary] = ThemeRGBA(hex: 0xFFD166)
        custom.dark[.surfaceTop] = ThemeRGBA(hex: 0x58432A)
        custom.dark.fontDesign = .rounded
        try render(AnyView(RadioWidgetView(entry: radio(theme: custom), familyOverride: .systemMedium)), theme: custom, family: .systemMedium, scheme: .dark, name: "custom-radio-medium")
        let theme = SharedThemeDefinition.builtIn(.neuro)
        for (name, count) in [("zero", 0 as Int?), ("large", 123456789), ("unavailable", nil)] {
            var entry = radio(theme: theme)
            entry.snapshot.title = "A very long song title that must stay inside the information column and truncate without shrinking into tiny text"
            entry.snapshot.artist = ""
            entry.snapshot.listeners = count
            entry.snapshot.fetchedAt = Date(timeIntervalSince1970: 1000)
            try render(AnyView(RadioWidgetView(entry: entry, familyOverride: .systemMedium)), theme: theme, family: .systemMedium, scheme: .dark, name: "failure-\(name)", width: 320)
        }
        for mode in [WidgetRenderingMode.accented, .vibrant] {
            try render(AnyView(RadioWidgetView(entry: radio(theme: theme), familyOverride: .systemMedium)), theme: theme, family: .systemMedium, scheme: .light, name: "constrained-\(mode)", renderingMode: mode)
        }
        for locale in ["de", "ja", "ar", "zh-Hans"] {
            try render(AnyView(RadioWidgetView(entry: radio(theme: theme), familyOverride: .systemMedium)), theme: theme, family: .systemMedium, scheme: .dark, name: "accessibility-\(locale)", width: 320, dynamicType: .accessibility1, locale: locale)
        }
        try render(AnyView(RadioWidgetView(entry: RadioWidgetEntry(), familyOverride: .systemMedium)), theme: .builtIn(.light), family: .systemMedium, scheme: .light, name: "first-launch-no-metadata")
    }
    /// Checks both outer bounds and progress-region pixels across playing and paused snapshots.
    @MainActor func testPlaybackLayoutStaysStableWhenPaused() throws {
        var snapshot = PlaybackWidgetSnapshot(
            song: WidgetSong(id: "song", title: "Wake Me Up Before You Go-Go", artist: "Wham!"),
            isPlaying: true, hasPrevious: true, hasNext: true
        )
        // Use a completed interval so timer advancement cannot change fill pixels.
        snapshot.updatedAt = Date().addingTimeInterval(-360)
        snapshot.elapsedSeconds = 180
        snapshot.durationSeconds = 180
        for family in [WidgetFamily.systemMedium, .systemLarge] {
            var sizes: [CGSize] = []
            var progressRegions: [Data] = []
            for isPlaying in [true, false] {
                snapshot.isPlaying = isPlaying
                let view = WidgetThemedView(theme: .builtIn(.dark)) {
                    PlaybackWidgetView(snapshot: snapshot, familyOverride: family)
                }
                .fixedSize(horizontal: false, vertical: true)
                let renderer = ImageRenderer(content: view)
                renderer.proposedSize = ProposedViewSize(width: 332, height: nil)
                let image = try XCTUnwrap(renderer.uiImage)
                sizes.append(image.size)
                // Includes artwork, metadata, and the progress bar, stopping before
                // the transport row whose play/pause symbol is expected to change.
                let region = CGRect(x: 0, y: 0, width: image.size.width,
                                    height: family == .systemLarge ? 84 : 64)
                let crop = try XCTUnwrap(image.cgImage?.cropping(to: region))
                progressRegions.append(try XCTUnwrap(UIImage(cgImage: crop).pngData()))
                let attachment = XCTAttachment(image: image)
                attachment.name = "playback-\(label(family))-\(isPlaying ? "playing" : "paused")"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            XCTAssertEqual(sizes[0], sizes[1], "Play/pause must preserve the widget's intrinsic layout in \(label(family))")
            XCTAssertEqual(progressRegions[0], progressRegions[1],
                           "Progress and metadata must not move within the widget's bounds in \(label(family))")
        }
    }
    @MainActor private func radio(theme: SharedThemeDefinition) -> RadioWidgetEntry {
        var snapshot = WidgetRadioSnapshot()
        snapshot.title = "Wake Me Up Before You Go-Go"
        snapshot.artist = "Wham!"
        snapshot.listeners = 42
        snapshot.fetchedAt = Date(timeIntervalSince1970: 1_791_733_200)
        return RadioWidgetEntry(snapshot: snapshot, theme: theme)
    }
    @MainActor private func label(_ family: WidgetFamily) -> String {
        switch family { case .systemSmall: "small"; case .systemLarge: "large"; default: "medium" }
    }
    @MainActor private func render(_ content: AnyView, theme: SharedThemeDefinition, family: WidgetFamily, scheme: ColorScheme, name: String, width: Double? = nil, renderingMode: WidgetRenderingMode = .fullColor, dynamicType: DynamicTypeSize = .large, locale: String = "en") throws {
        let size = CGSize(width: width ?? (family == .systemSmall ? 170 : 364), height: family == .systemLarge ? 376 : 170)
        let variant = theme.variant(for: scheme)
        let view = WidgetThemedView(theme: theme) { content }
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background { WidgetThemeSurface(theme: theme, variant: variant, fullColor: renderingMode == .fullColor) }
            .containerShape(RoundedRectangle(cornerRadius: 28))
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .environment(\.colorScheme, scheme)
            .environment(\.widgetRenderingMode, renderingMode)
            .environment(\.dynamicTypeSize, dynamicType)
            .environment(\.locale, Locale(identifier: locale))
            .environment(\.layoutDirection, locale == "ar" ? .rightToLeft : .leftToRight)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage, name)
        XCTAssertEqual(image.size, size)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
