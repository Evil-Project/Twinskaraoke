import Foundation

nonisolated struct BandleResult: Decodable, Sendable {
    let won: Bool?
    let attempts: [BandleAttempt]?
    let mediaListDTO: Media?
    let attemptNumber: Int?
    let songId: String?
    let songTitle: String?
    let artist: String?
    let completedAt: String
    let timeSpent: String?
    let challengeDate: String?
    let invalidChallengeReimbursement: Int?

    init(
        completedAt: String,
        won: Bool? = nil,
        attempts: [BandleAttempt]? = nil,
        mediaListDTO: Media? = nil,
        attemptNumber: Int? = nil,
        songId: String? = nil,
        songTitle: String? = nil,
        artist: String? = nil,
        timeSpent: String? = nil,
        challengeDate: String? = nil,
        invalidChallengeReimbursement: Int? = nil
    ) {
        self.won = won
        self.attempts = attempts
        self.mediaListDTO = mediaListDTO
        self.attemptNumber = attemptNumber
        self.songId = songId
        self.songTitle = songTitle
        self.artist = artist
        self.completedAt = completedAt
        self.timeSpent = timeSpent
        self.challengeDate = challengeDate
        self.invalidChallengeReimbursement = invalidChallengeReimbursement
    }

    var artworkURL: URL? {
        ArtworkURLBuilder.imageURL(
            cloudflareID: mediaListDTO?.cloudflareId,
            path: mediaListDTO?.absolutePath,
            variant: .hero
        )
    }
}
