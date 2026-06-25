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
            "Saving artwork"
        case .success:
            "Artwork saved"
        case .failed:
            "Artwork save failed"
        case .idle:
            "Save artwork"
        }
    }
}
