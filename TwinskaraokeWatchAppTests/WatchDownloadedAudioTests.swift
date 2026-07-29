import Foundation
import Testing
@testable import Twinskaraoke_Watch_App

/// Filing a finished download into the audio cache.
///
/// This is the step that has to happen inside URLSession's completion handler:
/// the downloaded file is reclaimed the moment that handler returns. Doing it
/// after a hop to the main queue silenced every non-radio song on device — the
/// file was gone by the time we looked, so the header read failed and playback
/// was dropped without a spinner, an error, or a sound.
@Suite("Watch downloaded audio")
struct WatchDownloadedAudioTests {
    @Test("A finished download is filed under its cache name")
    func filesValidAudio() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let temp = directory.appendingPathComponent("CFNetworkDownload_abc123.tmp")
        try mp3Payload().write(to: temp)
        let destination = directory.appendingPathComponent("song.mp3")

        #expect(AudioManager.storeDownloadedAudio(tempURL: temp, destinationURL: destination))
        #expect(FileManager.default.fileExists(atPath: destination.path))
        #expect(try Data(contentsOf: destination) == mp3Payload())
        #expect(!FileManager.default.fileExists(atPath: temp.path))
    }

    /// The exact state the old main-queue hop left behind. It has to fail
    /// closed rather than file an empty entry that would then fail to play.
    @Test("A temp file URLSession has already reclaimed is refused")
    func refusesReclaimedTempFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let vanished = directory.appendingPathComponent("CFNetworkDownload_gone.tmp")
        let destination = directory.appendingPathComponent("song.mp3")

        #expect(!AudioManager.storeDownloadedAudio(tempURL: vanished, destinationURL: destination))
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    /// A captive-portal page or a JSON error body arrives with a 200 and would
    /// otherwise be cached as if it were the song.
    @Test("A response body that is not audio never reaches the cache")
    func refusesNonAudioBody() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let temp = directory.appendingPathComponent("CFNetworkDownload_html.tmp")
        try Data("<!doctype html><title>Sign in</title>".utf8).write(to: temp)
        let destination = directory.appendingPathComponent("song.mp3")

        #expect(!AudioManager.storeDownloadedAudio(tempURL: temp, destinationURL: destination))
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(!FileManager.default.fileExists(atPath: temp.path))
    }

    /// URLSession calls back on its own queue, not the main one. If this ever
    /// stops compiling, the store has been pulled back onto the main actor and
    /// the hop that lost the file is back.
    @Test("Filing runs off the main actor, where URLSession calls back")
    func runsOffTheMainActor() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let temp = directory.appendingPathComponent("CFNetworkDownload_bg.tmp")
        try mp3Payload().write(to: temp)
        let destination = directory.appendingPathComponent("song.mp3")

        let stored = await Task.detached {
            AudioManager.storeDownloadedAudio(tempURL: temp, destinationURL: destination)
        }.value

        #expect(stored)
    }

    /// An ID3v2 tag, which is how the storage host serves these files.
    private func mp3Payload() -> Data {
        var bytes: [UInt8] = [0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3E]
        bytes.append(contentsOf: [UInt8](repeating: 0x00, count: 64))
        return Data(bytes)
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("downloaded-audio-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
