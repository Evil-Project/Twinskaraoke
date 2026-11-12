import Foundation
import Testing
@testable import Twinskaraoke

/// The upload sheet's state against a stub service: no file is read and no
/// request is sent.
@MainActor
@Suite("Upload song form")
struct UploadSongFormModelTests {
    private static func limits(songs: Int = 3, maxSongs: Int = 50, usedBytes: Int64 = 0, maxBytes: Int64 = 100_000_000) -> UploadLimits {
        UploadLimits(
            maxSongs: maxSongs,
            maxStorageBytes: maxBytes,
            usedStorageBytes: usedBytes,
            currentSongCount: songs,
            currentPlaylistCount: 0,
            playlistLimit: 10,
            songPerPlaylistLimit: 100
        )
    }

    private func model(
        limits: @escaping () throws -> UploadLimits = { limits() },
        size: Int64? = 1000,
        tags: UploadSongFormModel.FileTags = .init()
    ) -> UploadSongFormModel {
        UploadSongFormModel(service: UploadSongFormModel.Service(
            limits: { try limits() },
            fileSize: { _ in size },
            tags: { _ in tags }
        ))
    }

    private let file = URL(fileURLWithPath: "/picked/My Song.mp3")

    @Test func submitDisabledWithoutFile() async {
        let form = model()
        await form.loadLimits()
        #expect(!form.canSubmit)
        #expect(form.submission == nil)
        await form.pick(file)
        #expect(form.canSubmit)
        #expect(form.submission == .file(file, SongUploadMetadata(title: "My Song", artist: "", playlistID: nil)))
    }

    @Test("Submitting a file or link that is already uploading keeps the form open and says so")
    func submittingDuplicateIsRefused() async {
        let harness = SongUploadControllerTests.Harness()
        let controller = harness.controller()
        let form = model()
        await form.loadLimits()
        await form.pick(file)
        #expect(form.submit(to: controller))
        #expect(!form.isAlreadyUploading)
        #expect(!form.submit(to: controller))
        #expect(form.isAlreadyUploading)
        #expect(controller.uploads.count == 1)

        // A new choice clears the message.
        form.mode = .link
        #expect(!form.isAlreadyUploading)
        form.linkText = "https://youtu.be/abc"
        #expect(form.submit(to: controller))
        #expect(!form.submit(to: controller))
        #expect(form.isAlreadyUploading)
        form.linkText = "https://youtu.be/other"
        #expect(!form.isAlreadyUploading)
        #expect(controller.uploads.count == 2)
    }

    @Test("A slow size read of an earlier file doesn't replace a later pick")
    func laterPickWinsOverSlowSizeRead() async {
        let first = URL(fileURLWithPath: "/picked/First.mp3")
        let gate = AsyncStream<Void>.makeStream()
        let reading = ReadFlag()
        let form = UploadSongFormModel(service: UploadSongFormModel.Service(
            limits: { Self.limits() },
            fileSize: { url in
                if url == first {
                    reading.started = true
                    for await _ in gate.stream { break }
                }
                return 1000
            },
            tags: { _ in .init() }
        ))
        let slow = Task { await form.pick(first) }
        while !reading.started { await Task.yield() }
        await form.pick(file)
        gate.continuation.yield()
        await slow.value
        #expect(form.file?.url == file)
        #expect(form.title == "My Song")
    }

    @MainActor
    private final class ReadFlag {
        var started = false
    }

    @Test func submitDisabledWithUnsupportedLink() async {
        let form = model()
        await form.loadLimits()
        form.mode = .link
        form.linkText = "https://example.com/video"
        #expect(form.linkProblem == .unsupportedSite)
        #expect(!form.canSubmit)
        form.linkText = "  https://youtu.be/abc  "
        #expect(form.linkProblem == nil)
        #expect(form.canSubmit)
        #expect(form.submission == .link("https://youtu.be/abc"))
    }

    @Test func discordMessageLinkExplainsItself() {
        let form = model()
        form.mode = .link
        form.linkText = "https://discord.com/channels/1/2/3"
        #expect(form.linkProblem == .discordMessageLink)
        let message = SongUploadFailure.unsupportedLink(.discordMessageLink).userMessage
        #expect(message.localizedCaseInsensitiveContains("attachment"))
        #expect(message != SongUploadFailure.unsupportedLink(.unsupportedSite).userMessage)
        #expect(!form.canSubmit)
    }

    @Test func titlePrefillsFromFileNameWhenTagsAreMissing() async {
        let form = model()
        await form.pick(file)
        #expect(form.title == "My Song")
        #expect(form.artist.isEmpty)
        // A second file replaces a title the form filled in, not one typed.
        await form.pick(URL(fileURLWithPath: "/picked/Other.m4a"))
        #expect(form.title == "Other")
        form.title = "Typed"
        await form.pick(file)
        #expect(form.title == "Typed")
    }

    @Test func tagsPrefillEmptyFieldsOnly() async {
        let form = model(tags: .init(title: "Tag Title", artist: "Tag Artist"))
        form.artist = "Typed Artist"
        await form.pick(file)
        #expect(form.title == "Tag Title", "A tag beats the file name the form filled in.")
        #expect(form.artist == "Typed Artist")

        let typed = model(tags: .init(title: "Tag Title", artist: "Tag Artist"))
        typed.title = "Typed Title"
        await typed.pick(file)
        #expect(typed.title == "Typed Title")
        #expect(typed.artist == "Tag Artist")
    }

    @Test func oversizeFileShowsStorageMessage() async {
        let form = model(limits: { Self.limits(usedBytes: 99_000_000) }, size: 5_000_000)
        await form.loadLimits()
        await form.pick(file)
        #expect(form.quotaProblem == .quotaStorage(remaining: 1_000_000, needed: 5_000_000))
        #expect(form.quotaMessage != nil)
        #expect(!form.canSubmit)
        // Link imports aren't measured against storage before they run.
        form.mode = .link
        form.linkText = "https://www.youtube.com/watch?v=abc"
        #expect(form.quotaProblem == nil)
        #expect(form.canSubmit)
    }

    @Test func fullSongCountBlocksSubmit() async {
        let form = model(limits: { Self.limits(songs: 50) })
        await form.loadLimits()
        await form.pick(file)
        #expect(form.quotaProblem == .quotaSongs(max: 50))
        #expect(!form.canSubmit)
        form.mode = .link
        form.linkText = "https://youtu.be/abc"
        #expect(!form.canSubmit)
    }

    @Test func limitsFailureDoesNotBlockSubmit() async {
        let form = model(limits: { throw URLError(.notConnectedToInternet) })
        await form.loadLimits()
        #expect(form.limits == nil)
        #expect(form.limitsUnavailable)
        await form.pick(file)
        #expect(form.quotaProblem == nil)
        #expect(form.canSubmit)
    }

    @Test func fieldErrorMatchesCaseInsensitively() {
        let form = model()
        form.show(.server(status: 400, problem: UploadServerProblem(
            message: "Invalid",
            fieldErrors: ["title": ["Title is too long."], "ARTIST": ["Bad artist."]]
        )))
        #expect(form.fieldError("Title") == "Title is too long.")
        #expect(form.fieldError("artist") == "Bad artist.")
        #expect(form.fieldError("Url") == nil)
        form.show(.offline)
        #expect(form.fieldError("Title") == nil)
    }

    @Test func everyFailureHasItsOwnMessage() {
        let failures: [SongUploadFailure] = [
            .signedOut, .quotaSongs(max: 50), .quotaStorage(remaining: 10, needed: 20), .fileUnreadable,
            .offline, .timedOut, .interrupted, .server(status: 500, problem: nil), .rateLimited(retryAfter: nil),
            .unsupportedLink(.notALink), .unsupportedLink(.discordMessageLink), .unsupportedLink(.unsupportedSite),
            .unknown,
        ]
        let messages = failures.map(\.userMessage)
        #expect(messages.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        #expect(Set(messages).count == failures.count)
    }

    @Test func serverMessageIsShownWhenThereIsOne() {
        let problem = UploadServerProblem(message: "Unsupported platform.", fieldErrors: [:])
        #expect(SongUploadFailure.server(status: 400, problem: problem).userMessage == "Unsupported platform.")
        // Without a general message, the field's own says what to fix.
        let blank = UploadServerProblem(message: nil, fieldErrors: ["Title": ["Required."]])
        #expect(SongUploadFailure.server(status: 400, problem: blank).userMessage == "Required.")
    }
}
