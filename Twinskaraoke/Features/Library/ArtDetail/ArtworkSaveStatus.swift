import Foundation

enum ArtworkSaveStatus: Equatable {
    case idle
    case saving
    case success
    case failed(String)

    var isSaving: Bool {
        if case .saving = self { return true }
        return false
    }

    var accessibilityLabel: String {
        switch self {
        case .saving:
            String(localized: "Saving artwork")
        case .success:
            String(localized: "Artwork saved")
        case .failed:
            String(localized: "Artwork save failed")
        case .idle:
            String(localized: "Save artwork")
        }
    }
}
