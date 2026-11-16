import Foundation

nonisolated struct BandleHistoryEntry: Decodable, Identifiable, Sendable {
    let gameID: String?
    let userId: String?
    let guestId: String?
    let challengeDate: String?
    let mode: BandleMode?
    let dailySongId: String?
    let won: Bool?
    let attemptNumber: Int?
    let score: Int?
    let attemptsJson: String?
    let timeSpent: String?
    let gameStartedAt: String?
    let completedAt: String?
    let dailySong: BandleHistorySong?

    var id: String { gameID ?? challengeDate ?? dailySongId ?? "" }
    var challengeDay: DateComponents? { challengeDate.flatMap(KaraokeSetlist.day) }

    /// The challenge day as midnight UTC on the Gregorian calendar, which is
    /// how the server counts days. Format it in UTC too so it doesn't shift.
    var challengeDayDate: Date? {
        challengeDay.flatMap { Self.gregorianUTC.date(from: $0) }
    }

    private static let gregorianUTC: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    init(
        gameID: String? = nil,
        userId: String? = nil,
        guestId: String? = nil,
        challengeDate: String? = nil,
        mode: BandleMode? = nil,
        dailySongId: String? = nil,
        won: Bool? = nil,
        attemptNumber: Int? = nil,
        score: Int? = nil,
        attemptsJson: String? = nil,
        timeSpent: String? = nil,
        gameStartedAt: String? = nil,
        completedAt: String? = nil,
        dailySong: BandleHistorySong? = nil
    ) {
        self.gameID = gameID
        self.userId = userId
        self.guestId = guestId
        self.challengeDate = challengeDate
        self.mode = mode
        self.dailySongId = dailySongId
        self.won = won
        self.attemptNumber = attemptNumber
        self.score = score
        self.attemptsJson = attemptsJson
        self.timeSpent = timeSpent
        self.gameStartedAt = gameStartedAt
        self.completedAt = completedAt
        self.dailySong = dailySong
    }

    private enum CodingKeys: String, CodingKey {
        case gameID = "id"
        case userId, guestId, challengeDate, mode, dailySongId, won, attemptNumber
        case score, attemptsJson, timeSpent, gameStartedAt, completedAt, dailySong
    }
}
