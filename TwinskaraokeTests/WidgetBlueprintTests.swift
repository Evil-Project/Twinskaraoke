import Foundation
import SwiftUI
import Testing
@testable import Twinskaraoke

@Suite("Widget blueprint storage", .serialized)
struct WidgetBlueprintTests {
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    @Test func allThemesRoundTripAcrossIndependentReaders() throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = WidgetSnapshotStore(directory: directory)
        for mode in AppearanceMode.allCases {
            let state = SharedThemeState(definition: .builtIn(mode))
            #expect(state.isValid)
            try writer.write(state)
            #expect(WidgetSnapshotStore(directory: directory).readTheme() == state)
            #expect(state.definition.colorScheme == mode.colorScheme)
        }
    }
    @Test func themeFallbackMigrationAndCustomDefinition() throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        #expect(store.readTheme() == .fallback)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("theme.json")
        for mode in AppearanceMode.allCases {
            try Data("{\"schemaVersion\":0,\"appearanceMode\":\"\(mode.rawValue)\"}".utf8).write(to: url)
            #expect(store.readTheme().definition.id == mode.rawValue)
            #expect(!store.hasCurrentThemeState)
            try store.write(store.readTheme())
            #expect(store.hasCurrentThemeState)
        }
        for bad in ["{broken", "{}", "{\"schemaVersion\":0,\"appearanceMode\":\"missing\"}"] {
            try Data(bad.utf8).write(to: url)
            #expect(store.readTheme() == .fallback)
        }
        var custom = SharedThemeDefinition.builtIn(.neuro)
        custom.id = "test-custom-amber"
        custom.dark[.primary] = ThemeRGBA(hex: 0xFFD166)
        custom.dark[.surfaceTop] = ThemeRGBA(hex: 0x58432A)
        custom.dark.artworkRadius = 7
        custom.dark.fontDesign = .rounded
        try store.write(SharedThemeState(definition: custom))
        #expect(store.readTheme().definition == custom)
        var invalid = SharedThemeState(definition: custom)
        invalid.schemaVersion = 99
        try JSONEncoder().encode(invalid).write(to: url)
        #expect(store.readTheme() == .fallback)
        invalid = SharedThemeState(definition: custom)
        invalid.definition.dark[.primary].red = -1
        try JSONEncoder().encode(invalid).write(to: url)
        #expect(store.readTheme() == .fallback)
        invalid.definition.dark.colors.removeValue(forKey: ThemeToken.text.rawValue)
        #expect(!invalid.isValid)
    }
    @MainActor @Test func customSelectionUsesTheSameAppPersistencePath() throws {
        let store = WidgetSnapshotStore()
        guard let directory = store.directory else { return } // Unsigned CI has no entitled container.
        let url = directory.appendingPathComponent("theme.json")
        let originalData = try? Data(contentsOf: url)
        let app = AppThemeStore.shared
        let original = app.definition
        let selection = UserDefaults.standard.string(forKey: AppearanceMode.storageKey)
        defer {
            app.apply(original)
            UserDefaults.standard.set(selection, forKey: AppearanceMode.storageKey)
            if let originalData { try? originalData.write(to: url, options: .atomic) }
            else { try? FileManager.default.removeItem(at: url) }
        }
        var custom = SharedThemeDefinition.builtIn(.evil)
        custom.id = "verification-custom-theme"
        custom.dark[.primary] = ThemeRGBA(hex: 0xFFD166)
        app.apply(custom)
        #expect(store.readTheme().definition == custom)
        #expect(UserDefaults.standard.string(forKey: AppearanceMode.storageKey) == custom.id)
        app.applySelection(custom.id)
        #expect(app.definition == custom)
    }
    @MainActor @Test func discoverableActionsCarryIndividualDescriptions() throws {
        let url = Bundle.main.bundleURL.appendingPathComponent("Metadata.appintents/extract.actionsdata")
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let actions = try #require(object["actions"] as? [String: [String: Any]])
        let discoverable = actions.filter { $0.key.hasPrefix("IOS") && $0.value["isDiscoverable"] as? Bool == true }
        #expect(discoverable.count == 15)
        for (name, action) in discoverable {
            let metadata = try #require(action["descriptionMetadata"] as? [String: Any], "Missing description: \(name)")
            let text = try #require(metadata["descriptionText"] as? [String: Any])
            let key = try #require(text["key"] as? String)
            #expect(!key.isEmpty)
            #expect(!key.hasSuffix(" in Twinskaraoke."))
        }
    }
    @Test func radioCountsAndMissingMetadata() throws {
        let date = Date(timeIntervalSince1970: 1000)
        for (listenerJSON, expected) in [("{\"total\":0}", 0 as Int?), ("{\"total\":123456789}", 123456789), ("{\"total\":-1}", nil), ("{\"total\":\"42\"}", nil), ("{\"total\":1.5}", nil), ("{\"total\":true}", nil), ("null", nil), ("{}", nil)] {
            let result = WidgetRadioSnapshot.decode(payload(listeners: listenerJSON), fetchedAt: date)
            #expect(result.snapshot.listeners == expected)
            #expect(result.snapshot.title == "A long live song")
            #expect(result.snapshot.artist.isEmpty)
            #expect(result.snapshot.fetchedAt == date)
            #expect(result.artworkURL == nil)
        }
        for bad in ["{}", "{broken", "{\"now_playing\":null}"] {
            #expect(WidgetRadioSnapshot.decode(Data(bad.utf8)).snapshot.fetchedAt == nil)
        }
    }
    @Test func failedFetchRetainsCachedSongCountArtworkAndTimestamp() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        var cached = WidgetRadioSnapshot.decode(payload(listeners: "{\"total\":0}"), fetchedAt: Date(timeIntervalSince1970: 1000)).snapshot
        cached.artworkFilename = "cached.jpg"
        try store.write(cached)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineRadioProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let result = await WidgetRadioRepository.fetch(store: store, session: session)
        #expect(result == cached)
        #expect(store.readRadio() == cached)
        let newer = WidgetRadioSnapshot.decode(payload(listeners: "{\"total\":42}"), fetchedAt: Date(timeIntervalSince1970: 2000)).snapshot
        try store.write(newer)
        #expect(await WidgetRadioRepository.cache(cached, store: store, session: session) == newer)
    }
    @Test func timestampChangesDoNotTriggerContentReloads() {
        var first = WidgetRadioSnapshot.decode(payload(listeners: "{\"total\":42}"), fetchedAt: Date(timeIntervalSince1970: 1000)).snapshot
        var second = first
        second.fetchedAt = Date(timeIntervalSince1970: 2000)
        #expect(first.hasSameContent(as: second))
        first.listeners = 0
        #expect(!first.hasSameContent(as: second))
    }
    @Test func columnsStayProportionalAcrossWidths() {
        for width in [260.0, 300, 332, 364, 500, 700] {
            let columns = RadioWidgetColumns(availableWidth: width, gap: 12)
            #expect(abs(columns.information / columns.listeners - 2) < 0.001)
            #expect(abs(columns.information + columns.listeners + 12 - width) < 0.001)
        }
    }
    private func payload(listeners: String) -> Data {
        Data("{\"station\":{\"name\":\"Radio\",\"listen_url\":\"https://example.invalid/live.mp3\"},\"listeners\":\(listeners),\"now_playing\":{\"song\":{\"id\":\"a\",\"title\":\"A long live song\",\"art\":\"http://example.invalid/art.jpg\"}}}".utf8)
    }
}

nonisolated private final class OfflineRadioProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}
