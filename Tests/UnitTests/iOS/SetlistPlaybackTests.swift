import Foundation
import Testing
@testable import Twinskaraoke

@MainActor
@Suite("Setlist playback")
struct SetlistPlaybackTests {
    /// Songs as the server sends a setlist's: out of sung order, each with its
    /// place in `order`.
    private func setlist(places: [Int] = [3, 1, 2]) -> KaraokeSetlist {
        let songs = places.map { place in
            UITestFixtures.song(id: "s\(place)", title: "Song \(place)", artist: "Artist").settingOrder(place)
        }
        return KaraokeSetlist(
            playlist: Playlist(id: "setlist", name: "Setlist", songCount: songs.count, mosaicMedia: nil, songListDTOs: songs),
            streamDay: nil,
            totalDuration: nil
        )
    }

    @Test("Play starts the first song sung and queues the rest in sung order, as the setlist")
    func playUsesSungOrder() {
        var played: (song: String, playlist: String, context: [String])?
        SetlistCardActions.play(setlist()) { song, playlist, context in
            played = (song.id, playlist.id, context.map(\.id))
        }
        #expect(played?.song == "s1")
        #expect(played?.playlist == "setlist")
        #expect(played?.context == ["s1", "s2", "s3"])
    }

    @Test("Shuffle hands over every song, as the setlist")
    func shuffleUsesTheSetlist() {
        var shuffled: (playlist: String, songs: [String])?
        SetlistCardActions.shuffle(setlist()) { playlist, songs in
            shuffled = (playlist.id, songs.map(\.id))
        }
        #expect(shuffled?.playlist == "setlist")
        #expect(shuffled?.songs == ["s1", "s2", "s3"])
    }

    @Test("Play starts nothing for a setlist without songs")
    func playWithoutSongs() {
        var calls = 0
        SetlistCardActions.play(setlist(places: [])) { _, _, _ in calls += 1 }
        #expect(calls == 0)
    }

    @Test("The row menus get the songs in sung order")
    func menuSongsInSungOrder() {
        #expect(setlist().songsInOrder.map(\.id) == ["s1", "s2", "s3"])
    }
}
