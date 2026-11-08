import Foundation

nonisolated enum UITestFixtures {
    static let coreSongs: [Song] = [
        song(
            id: "ui-song-wake-me-up",
            title: "Wake Me Up Before You Go-Go",
            originalArtists: ["Wham!"]
        ),
        song(
            id: "ui-song-hero",
            title: "Hero",
            originalArtists: ["Mili"]
        ),
        song(
            id: "ui-song-cure-for-me",
            title: "Cure For Me",
            originalArtists: ["AURORA"]
        ),
        song(
            id: "ui-song-be-my-star",
            title: "Be My Star",
            originalArtists: ["LEVEL NINE"]
        ),
        song(
            id: "ui-song-young-and-beautiful",
            title: "Young and Beautiful",
            originalArtists: ["Lana Del Rey"]
        ),
        song(
            id: "ui-song-send-me-an-angel",
            title: "Send Me an Angel",
            originalArtists: ["Scorpions"]
        ),
    ]

    static func song(
        id: String,
        title: String,
        originalArtists: [String],
        coverArtists: [String] = ["Neuro"],
        duration: Int = 210,
        userUploaded: Bool = true
    ) -> Song {
        Song(
            id: id,
            title: title,
            duration: duration,
            absolutePath: nil,
            cloudflareID: nil,
            coverArt: nil,
            originalArtists: originalArtists,
            coverArtists: coverArtists,
            userUploaded: userUploaded
        )
    }

    static func song(
        id: String,
        title: String,
        artist: String,
        duration: Int = 210,
        userUploaded: Bool = true
    ) -> Song {
        song(
            id: id,
            title: title,
            originalArtists: [artist],
            duration: duration,
            userUploaded: userUploaded
        )
    }

    static func playlist(id: String, name: String, songs: [Song]) -> Playlist {
        Playlist(
            id: id,
            name: name,
            songCount: songs.count,
            media: nil,
            mosaicMedia: nil,
            songListDTOs: songs
        )
    }

    /// Newest first, across two years, as the server sends them.
    static let setlists: [KaraokeSetlist] = [
        setlist(
            id: "ui-setlist-halloween",
            name: "Evil Halloween Karaoke - October 29, 2026 Setlist",
            day: "2026-10-29",
            songs: Array(coreSongs.prefix(4))
        ),
        setlist(
            id: "ui-setlist-drive",
            name: "Neuro Long Drive Mini Karaoke - October 16, 2026 Setlist",
            day: "2026-10-16",
            songs: Array(coreSongs.suffix(3))
        ),
        setlist(
            id: "ui-setlist-christmas",
            name: "Neuro Christmas Karaoke - December 25, 2025 Setlist",
            day: "2025-12-25",
            songs: Array(coreSongs.dropFirst(2).prefix(4))
        ),
    ]

    static func setlist(id: String, name: String, day: String, songs: [Song]) -> KaraokeSetlist {
        KaraokeSetlist(
            playlist: playlist(id: id, name: name, songs: songs),
            streamDay: KaraokeSetlist.day(from: day),
            totalDuration: songs.reduce(0) { $0 + $1.duration }
        )
    }
}
