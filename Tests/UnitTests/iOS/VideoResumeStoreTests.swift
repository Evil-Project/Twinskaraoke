import Foundation
import Testing
@testable import Twinskaraoke

/// Cover for the rules that decide what becomes a resume point.
///
/// The store itself talks to `UserDefaults` and to the signed-in account, so
/// the parts worth testing are the pure ones: what counts as worth resuming,
/// how the map is capped, and what a point reports about itself.
@Suite("Video resume points")
struct VideoResumeStoreTests {
    private static func makeVideo(id: String = "video-1") -> GalleryVideo {
        GalleryVideo(
            id: id,
            name: "Example",
            songId: nil,
            songTitle: nil,
            description: nil,
            url: nil,
            thumbnailUrl: nil,
            absolutePath: "a5f3c938-c3c4-49c0-9940-6fcd79f43e63",
            cloudflareId: nil,
            mP4: nil,
            contentType: nil,
            videoType: nil,
            createdBy: nil,
            creatorUserId: nil,
            creatorAvatarUrl: nil,
            createdDate: nil,
            duration: nil,
            width: nil,
            height: nil,
            isWatchalong: nil,
            category: nil,
            views: nil,
            upvotes: nil,
            commentCount: nil
        )
    }

    private static func makePoint(
        id: String = "video-1",
        position: TimeInterval = 60,
        duration: TimeInterval = 600,
        updatedAt: Date = Date()
    ) -> VideoResumePoint {
        VideoResumePoint(
            video: makeVideo(id: id),
            position: position,
            duration: duration,
            updatedAt: updatedAt
        )
    }

    // MARK: - What a position means

    @Test("A position past the floor and short of the end is resumable")
    func keepsMidVideoPosition() {
        #expect(VideoResumeStore.outcome(position: 300, duration: 600) == .resume)
    }

    @Test("Barely-started playback leaves no trace")
    func discardsPositionBelowFloor() {
        #expect(VideoResumeStore.outcome(position: 4, duration: 600) == .discard)
        #expect(VideoResumeStore.outcome(position: 0, duration: 600) == .discard)
    }

    @Test("The final seconds count as watched, not as somewhere to return to")
    func treatsCompletionTailAsWatched() {
        #expect(VideoResumeStore.outcome(position: 595, duration: 600) == .watched)
        #expect(VideoResumeStore.outcome(position: 600, duration: 600) == .watched)
    }

    /// `GalleryVideo.duration` is 0 or absent for ~1279 of the ~1385 catalogue
    /// items, so an unknown runtime is the common case, not an edge one — and
    /// it must not stop a position being remembered.
    @Test("An unknown runtime still resumes, judged on the floor alone")
    func keepsPositionWhenDurationUnknown() {
        #expect(VideoResumeStore.outcome(position: 300, duration: 0) == .resume)
        #expect(VideoResumeStore.outcome(position: 4, duration: 0) == .discard)
    }

    /// Nothing about a 15-second clip is resumable: the floor and the
    /// completion tail meet, so every position is one or the other.
    @Test("A clip too short to have a resumable middle never yields one")
    func neverResumesInAShortClip() {
        for position in stride(from: 0.0, through: 15.0, by: 1) {
            #expect(VideoResumeStore.outcome(position: position, duration: 15) != .resume)
        }
    }

    // MARK: - Watched history

    @Test("Over the limit, the oldest completions are the ones dropped")
    func trimmingWatchedKeepsTheMostRecent() {
        let start = Date(timeIntervalSince1970: 0)
        let overflow = VideoResumeStore.watchedLimit + 10
        let watched = Dictionary(uniqueKeysWithValues: (0 ..< overflow).map { index in
            ("video-\(index)", start.addingTimeInterval(TimeInterval(index)))
        })

        let trimmed = VideoResumeStore.trimmedWatched(watched)

        #expect(trimmed.count == VideoResumeStore.watchedLimit)
        #expect(trimmed["video-\(overflow - 1)"] != nil)
        #expect(trimmed["video-0"] == nil)
    }

    /// Completions are an ID and a date, so their budget is far larger than the
    /// resume map's — and the two must not share one, or finishing videos would
    /// evict the ones still in progress.
    @Test("Completions get their own, larger budget")
    func watchedBudgetIsSeparateAndLarger() {
        #expect(VideoResumeStore.watchedLimit > VideoResumeStore.entryLimit)
    }

    // MARK: - Capping

    @Test("Over the limit, the oldest entries are the ones dropped")
    func trimmingKeepsTheMostRecent() {
        let start = Date(timeIntervalSince1970: 0)
        let overflow = VideoResumeStore.entryLimit + 10
        let points = (0 ..< overflow).map { index in
            Self.makePoint(
                id: "video-\(index)",
                updatedAt: start.addingTimeInterval(TimeInterval(index))
            )
        }
        let map = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0) })

        let trimmed = VideoResumeStore.trimmed(map)

        #expect(trimmed.count == VideoResumeStore.entryLimit)
        #expect(trimmed["video-\(overflow - 1)"] != nil)
        #expect(trimmed["video-0"] == nil)
    }

    @Test("A map inside the limit is returned untouched")
    func trimmingLeavesSmallMapsAlone() {
        let map = ["video-1": Self.makePoint()]
        #expect(VideoResumeStore.trimmed(map) == map)
    }

    // MARK: - Point arithmetic

    @Test("Fraction and remaining time are reported against the measured runtime")
    func reportsProgressAgainstDuration() {
        let point = Self.makePoint(position: 150, duration: 600)
        #expect(point.fraction == 0.25)
        #expect(point.remaining == 450)
    }

    /// A bar drawn from a `nil` fraction would read as "not started", which is a
    /// different claim from "we do not know how long this is".
    @Test("An unknown runtime reports no fraction rather than zero")
    func reportsNoProgressWithoutDuration() {
        let point = Self.makePoint(position: 150, duration: 0)
        #expect(point.fraction == nil)
        #expect(point.remaining == nil)
    }

    @Test("A position past the measured runtime clamps instead of overflowing")
    func clampsFractionToOne() {
        let point = Self.makePoint(position: 900, duration: 600)
        #expect(point.fraction == 1)
        #expect(point.remaining == 0)
    }

    // MARK: - Persistence shape

    @Test("A point round-trips through JSON with its video intact")
    func encodesAndDecodes() throws {
        let point = Self.makePoint(position: 123.5, duration: 456.5)
        let data = try JSONEncoder().encode(["video-1": point])
        let decoded = try JSONDecoder().decode([String: VideoResumePoint].self, from: data)

        #expect(decoded["video-1"]?.position == 123.5)
        #expect(decoded["video-1"]?.duration == 456.5)
        #expect(decoded["video-1"]?.video.id == "video-1")
        #expect(decoded["video-1"]?.video.streamURL == point.video.streamURL)
    }
}
