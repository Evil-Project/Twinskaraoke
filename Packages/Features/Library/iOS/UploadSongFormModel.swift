import AVFoundation
import Foundation
import Observation

/// What the upload sheet holds before it hands a song to
/// `SongUploadController`: a picked file with its title and artist, or a
/// link, and the user's quota.
///
/// Problems the form can see for itself, an unsupported link or a full
/// quota, keep the sheet's submit button off. Limits that can't be loaded
/// don't: the server decides then.
@MainActor
@Observable
final class UploadSongFormModel {
    enum Mode: Hashable {
        case file
        case link
    }

    struct PickedFile: Equatable {
        let url: URL
        let name: String
        /// `nil` when the size couldn't be read.
        let size: Int64?
    }

    /// The title and artist a file's own tags carry, if any.
    nonisolated struct FileTags: Sendable, Equatable {
        var title: String?
        var artist: String?
    }

    /// What submitting hands to the controller.
    enum Submission: Equatable {
        case file(URL, SongUploadMetadata)
        case link(String)
    }

    struct Service {
        var limits: @MainActor () async throws -> UploadLimits
        /// The picked file's size, read under its security scope.
        var fileSize: @MainActor (_ file: URL) -> Int64?
        var tags: @MainActor (_ file: URL) async -> FileTags

        static var live: Service {
            Service(
                limits: { try await KaraokeAPIClient.uploadLimits() },
                fileSize: { file in
                    let scoped = file.startAccessingSecurityScopedResource()
                    defer { if scoped { file.stopAccessingSecurityScopedResource() } }
                    return (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
                },
                tags: { file in await UploadSongFormModel.readTags(file) }
            )
        }

        /// No network and no files, for UI tests launched with `-UITestMode`.
        static var uiTestFixture: Service {
            Service(
                limits: { UITestFixtures.uploadLimits },
                fileSize: { _ in 4_200_000 },
                tags: { _ in FileTags() }
            )
        }
    }

    var mode: Mode = .file
    private(set) var file: PickedFile?
    var title = ""
    var artist = ""
    var linkText = ""
    private(set) var limits: UploadLimits?
    private(set) var limitsUnavailable = false
    /// What the server said about a failed attempt, for messages under the
    /// fields it names.
    private(set) var serverProblem: UploadServerProblem?

    @ObservationIgnored private let service: Service
    /// The values the form filled in itself, which a later file or its tags
    /// may replace; anything the user typed stays.
    @ObservationIgnored private var filledTitle = ""
    @ObservationIgnored private var filledArtist = ""

    init(service: Service = AppRuntime.isUITestMode ? .uiTestFixture : .live) {
        self.service = service
    }

    func loadLimits() async {
        do {
            limits = try await service.limits()
            limitsUnavailable = false
        } catch {
            limitsUnavailable = limits == nil
            DebugLogger.log("Upload limits failed to load: \(type(of: error))", category: .network)
        }
    }

    /// Takes a file from the picker. The title starts as the file's name,
    /// which the server would otherwise leave blank, and the file's tags
    /// then fill the fields the user hasn't typed in.
    func pick(_ url: URL) async {
        file = PickedFile(url: url, name: url.lastPathComponent, size: service.fileSize(url))
        serverProblem = nil
        fill(title: SongUploadMetadata.defaultTitle(forFilename: url.lastPathComponent) ?? "", artist: "")
        let tags = await service.tags(url)
        guard file?.url == url else { return }
        fill(title: tags.title ?? filledTitle, artist: tags.artist ?? filledArtist)
    }

    private func fill(title newTitle: String, artist newArtist: String) {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title == filledTitle {
            title = newTitle
            filledTitle = newTitle
        }
        if artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || artist == filledArtist {
            artist = newArtist
            filledArtist = newArtist
        }
    }

    // MARK: - Derived state

    /// Why the link can't be imported; `nil` while the field is empty.
    var linkProblem: SongLinkImport.LinkProblem? {
        guard !linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return SongLinkImport.problem(with: linkText)
    }

    /// The quota this song would exceed. A link's size isn't known until the
    /// server has downloaded it, so only the song count applies to it.
    var quotaProblem: SongUploadFailure? {
        guard let limits else { return nil }
        let size = mode == .file ? file?.size ?? 0 : 0
        return limits.blocking(fileSize: size)
    }

    var quotaMessage: String? {
        quotaProblem?.userMessage
    }

    var canSubmit: Bool {
        submission != nil
    }

    var submission: Submission? {
        guard quotaProblem == nil else { return nil }
        switch mode {
        case .file:
            guard let file else { return nil }
            return .file(file.url, SongUploadMetadata(title: title, artist: artist, playlistID: nil))
        case .link:
            guard let link = SongLinkImport.supportedLink(linkText) else { return nil }
            return .link(link.absoluteString)
        }
    }

    /// Keeps the field messages of a server answer for display.
    func show(_ failure: SongUploadFailure) {
        if case let .server(_, problem) = failure {
            serverProblem = problem
        } else {
            serverProblem = nil
        }
    }

    /// The server's message for `field`, whatever case it named it in.
    func fieldError(_ field: String) -> String? {
        serverProblem?.message(forField: field)
    }

    // MARK: - Tags

    /// The common title and artist tags of `file`, trimmed; read off the
    /// main actor, under the file's security scope.
    @concurrent
    nonisolated static func readTags(_ file: URL) async -> FileTags {
        let scoped = file.startAccessingSecurityScopedResource()
        defer { if scoped { file.stopAccessingSecurityScopedResource() } }
        guard let items = try? await AVURLAsset(url: file).load(.commonMetadata) else { return FileTags() }
        func value(_ identifier: AVMetadataIdentifier) async -> String? {
            guard let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier).first,
                  let text = try? await item.load(.stringValue)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else { return nil }
            return text
        }
        return await FileTags(title: value(.commonIdentifierTitle), artist: value(.commonIdentifierArtist))
    }
}

extension UploadServerProblem {
    /// The messages for `field`, matched without regard to case, since the
    /// server's casing of field names isn't specified.
    func message(forField field: String) -> String? {
        let messages = fieldErrors.first { $0.key.caseInsensitiveCompare(field) == .orderedSame }?.value ?? []
        return messages.isEmpty ? nil : messages.joined(separator: " ")
    }
}
