import SwiftUI
import Observation

@MainActor
@Observable
final class PlaybackRowState {
    static let shared = PlaybackRowState()

    private(set) var currentSongID: String?
    private(set) var isPlaying = false
    private(set) var isRadioMode = false
    private(set) var radioArtworkURL: URL?

    @ObservationIgnored private var observation: ObservationToken?

    private init() {
        observation = observeContinuously({
            let manager = AudioPlayerManager.shared
            _ = manager.currentSong
            _ = manager.isPlaying
            _ = manager.isRadioMode
            _ = manager.radioArtworkURL
        }, onChange: { [weak self] in
            self?.syncFromPlayer()
        })
        syncFromPlayer()
    }
    private func syncFromPlayer() {
        let manager = AudioPlayerManager.shared
        let songID = manager.currentSong?.id
        if currentSongID != songID { currentSongID = songID }
        if isPlaying != manager.isPlaying { isPlaying = manager.isPlaying }
        if isRadioMode != manager.isRadioMode { isRadioMode = manager.isRadioMode }
        if radioArtworkURL != manager.radioArtworkURL { radioArtworkURL = manager.radioArtworkURL }
    }

    func displayImageURL(for song: Song, variant: ArtworkImageVariant = .card) -> URL? {
        _ = FallbackArtRevision.shared.revision
        if isRadioMode, currentSongID == song.id, let radioArtworkURL {
            return ArtworkURLBuilder.variantURL(from: radioArtworkURL, variant: variant) ?? radioArtworkURL
        }
        switch variant {
        case .row:
            return song.rowImageURL
        case .thumbnail:
            return song.thumbnailURL
        case .hero:
            return song.heroImageURL
        case .fullHD:
            return song.fullHDImageURL
        default:
            return song.imageURL
        }
    }
}
