import Foundation
import Testing
@testable import Twinskaraoke

@MainActor
@Suite("Setlist playback")
struct SetlistPlaybackTests {
    /// A setlist decoded from songs sent the way the server sends them: out of
    /// sung order, each with its place in `order`.
    private func setlist(places: [Int] = [3, 1, 2]) throws -> KaraokeSetlist {
        let songs = places.map { #"{"id":"s\#($0)","title":"Song \#($0)","order":\#($0)}"# }.joined(separator: ",")
        let json = #"{"id":"setlist","name":"Setlist","songListDTOs":[\#(songs)]}"#
        return try JSONDecoder().decode(KaraokeSetlist.self, from: Data(json.utf8))
    }

    @Test("Play starts the first song sung and queues the rest in sung order, as the setlist")
    func playUsesSungOrder() throws {
        var played: (song: String, playlist: String, context: [String])?
        try SetlistCardActions.play(setlist()) { song, playlist, context in
            played = (song.id, playlist.id, context.map(\.id))
        }
        #expect(played?.song == "s1")
        #expect(played?.playlist == "setlist")
        #expect(played?.context == ["s1", "s2", "s3"])
    }

    @Test("Shuffle hands over every song, as the setlist")
    func shuffleUsesTheSetlist() throws {
        var shuffled: (playlist: String, songs: [String])?
        try SetlistCardActions.shuffle(setlist()) { playlist, songs in
            shuffled = (playlist.id, songs.map(\.id))
        }
        #expect(shuffled?.playlist == "setlist")
        #expect(shuffled?.songs == ["s1", "s2", "s3"])
    }

    @Test("Play starts nothing for a setlist without songs")
    func playWithoutSongs() throws {
        var calls = 0
        try SetlistCardActions.play(setlist(places: [])) { _, _, _ in calls += 1 }
        #expect(calls == 0)
    }
}
