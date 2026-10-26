import Testing
import UIKit
import Foundation
@testable import Twinskaraoke

@MainActor
struct AppIconManagerTests {
    @Test func compiledIconsAndPreviewsAreBundled() {
        let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        let primaryName = primary?["CFBundleIconName"] as? String
        #expect(primaryName == "AppIcon")
        let alternates = icons?["CFBundleAlternateIcons"] as? [String: Any]
        let alternateName = AppIconChoice.experimental.alternateIconName!
        #expect(Set(alternates?.keys.map { $0 } ?? []) == [alternateName])
        for choice in AppIconChoice.allCases {
            for dark in [false, true] {
                #expect(UIImage(named: choice.previewName(dark: dark)) != nil)
            }
        }
    }

    @Test func defaultAndAlternate() async {
        let app = FakeIconApplication()
        let manager = AppIconManager(application: app)
        #expect(manager.selected == .production)
        await manager.select(.experimental)
        #expect(app.alternateIconName == "ExperimentalAppIcon")
        #expect(manager.selected == .experimental)
        await manager.select(.production)
        #expect(app.alternateIconName == nil)
        #expect(manager.selected == .production)
        #expect(app.requests.count == 2)
    }

    @Test func failedChangeKeepsActualIconAndAllowsRetry() async {
        let app = FakeIconApplication()
        let manager = AppIconManager(application: app)
        app.shouldFail = true
        await manager.select(.experimental)
        #expect(manager.selected == .production)
        #expect(manager.errorMessage != nil)
        #expect(!manager.isChanging)
        app.shouldFail = false
        await manager.select(.experimental)
        #expect(manager.selected == .experimental)
        #expect(manager.errorMessage == nil)
        app.shouldFail = true
        await manager.select(.production)
        #expect(manager.selected == .experimental)
        #expect(!manager.isChanging)
    }

    @Test func relaunchAndNoOp() async {
        let app = FakeIconApplication()
        app.alternateIconName = "ExperimentalAppIcon"
        let manager = AppIconManager(application: app)
        #expect(manager.selected == .experimental)
        await manager.select(.experimental)
        #expect(app.requests.isEmpty)
        app.supportsAlternateIcons = false
        await manager.select(.production)
        #expect(app.requests.isEmpty)
        #expect(manager.selected == .experimental)
    }

    @Test func concurrentChangesAreIgnored() async {
        let app = FakeIconApplication()
        let manager = AppIconManager(application: app)
        app.duringChange = {
            #expect(manager.isChanging)
            await manager.select(.production)
        }
        await manager.select(.experimental)
        #expect(app.requests.count == 1)
        #expect(manager.selected == .experimental)
        #expect(!manager.isChanging)
    }
}

@MainActor
private final class FakeIconApplication: AppIconApplication {
    var supportsAlternateIcons = true
    var alternateIconName: String?
    var requests = [String?]()
    var shouldFail = false
    var duringChange: (() async -> Void)?

    func changeIcon(to name: String?) async throws {
        requests.append(name)
        await duringChange?()
        if shouldFail { throw IconFailure.failed }
        alternateIconName = name
    }
    enum IconFailure: Error { case failed }
}
