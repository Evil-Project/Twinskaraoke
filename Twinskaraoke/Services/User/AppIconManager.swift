import Observation
import UIKit

enum AppIconChoice: String, CaseIterable, Identifiable {
    case production
    case experimental

    var id: String { rawValue }
    var title: String { self == .production ? "Original" : "Experimental" }

    var alternateIconName: String? {
        switch self {
        case .production: nil
        case .experimental: "ExperimentalAppIcon"
        }
    }

    func previewName(dark: Bool) -> String {
        let name = self == .production ? "AppIcon" : "ExperimentalAppIcon"
        return name + (dark ? "PreviewDark" : "Preview")
    }
}

@MainActor
protocol AppIconApplication: AnyObject {
    var supportsAlternateIcons: Bool { get }
    var alternateIconName: String? { get }
    func changeIcon(to name: String?) async throws
}

extension UIApplication: AppIconApplication {
    func changeIcon(to name: String?) async throws {
        try await setAlternateIconName(name)
    }
}

/// The OS is the source of truth; failed changes never persist a false selection.
@MainActor
@Observable
final class AppIconManager {
    static let shared = AppIconManager()

    private(set) var selected: AppIconChoice = .production
    private(set) var isChanging = false
    private(set) var errorMessage: String?
    private let application: any AppIconApplication

    var isSupported: Bool { application.supportsAlternateIcons }

    init(application: any AppIconApplication = UIApplication.shared) {
        self.application = application
        refresh()
    }

    func refresh() {
        selected = application.alternateIconName == nil ? .production : .experimental
    }

    func clearError() { errorMessage = nil }

    func select(_ choice: AppIconChoice) async {
        guard !isChanging else { return }
        refresh()
        guard isSupported, selected != choice else { return }
        isChanging = true
        errorMessage = nil
        defer {
            refresh()
            isChanging = false
        }
        do {
            try await application.changeIcon(to: choice.alternateIconName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
