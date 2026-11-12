import Foundation

/// Where upload text is looked up outside a view: the language chosen in
/// the app, as download notifications do. `String(localized:)` otherwise
/// follows the device language, which the app's setting can override.
struct UploadLocalization {
    let bundle: Bundle
    let locale: Locale

    init(language: AppLanguage) {
        bundle = language.localizationBundle
        locale = Locale(identifier: language.localeIdentifier)
    }

    /// The language the app is set to in `defaults`.
    static func current(_ defaults: UserDefaults = .standard) -> UploadLocalization {
        UploadLocalization(language: AppLanguage(rawValue: defaults.string(forKey: AppLanguage.storageKey) ?? "") ?? .system)
    }
}

extension SongUploadFailure {
    /// What went wrong and what the user can do, in one or two sentences, in
    /// the app's language. The server's own message wins when it sent one.
    @MainActor var userMessage: String {
        userMessage(in: .current())
    }

    @MainActor func userMessage(in localization: UploadLocalization) -> String {
        let (bundle, locale) = (localization.bundle, localization.locale)
        return switch self {
        case .signedOut:
            String(localized: "Sign in to upload songs.", bundle: bundle, locale: locale)
        case let .quotaSongs(max):
            String(
                localized: "You've reached your limit of \(max) songs. Delete one to upload another.",
                bundle: bundle,
                locale: locale
            )
        case let .quotaStorage(remaining, needed):
            String(
                localized: "This file is \(Self.size(needed, locale: locale)), but only \(Self.size(remaining, locale: locale)) of your storage is left.",
                bundle: bundle,
                locale: locale
            )
        case .fileUnreadable:
            String(localized: "The file couldn't be read. Choose it again.", bundle: bundle, locale: locale)
        case .offline:
            String(localized: "You're offline. Connect to the internet and try again.", bundle: bundle, locale: locale)
        case .timedOut:
            String(localized: "The upload took too long. Try again.", bundle: bundle, locale: locale)
        case .interrupted:
            String(localized: "The upload was interrupted. Try again.", bundle: bundle, locale: locale)
        case let .server(status, problem):
            // A 400 can carry only field errors: the first one says more
            // than the generic text.
            problem?.message ?? problem?.firstFieldMessage ?? String(
                localized: "The server couldn't add the song (error \(status)). Try again later.",
                bundle: bundle,
                locale: locale
            )
        case .rateLimited:
            String(localized: "Too many uploads at once. Wait a moment, then try again.", bundle: bundle, locale: locale)
        case .unsupportedLink(.notALink):
            String(localized: "Enter a full link that starts with https://.", bundle: bundle, locale: locale)
        case .unsupportedLink(.discordMessageLink):
            String(
                localized: "This links to a Discord message. Copy the link of the attachment itself instead.",
                bundle: bundle,
                locale: locale
            )
        case .unsupportedLink(.unsupportedSite):
            String(localized: "Only YouTube, Bilibili and Discord attachment links can be imported.", bundle: bundle, locale: locale)
        case .unknown:
            String(localized: "Something went wrong. Try again.", bundle: bundle, locale: locale)
        }
    }

    /// A byte count the way Files shows it.
    nonisolated static func size(_ bytes: Int64, locale: Locale = .current) -> String {
        bytes.formatted(.byteCount(style: .file).locale(locale))
    }
}

nonisolated extension UploadServerProblem {
    /// The messages of the first field the server named: Title, then
    /// Artist, then the others by name, so the choice doesn't depend on the
    /// order the answer listed them in.
    var firstFieldMessage: String? {
        let leading = ["title", "artist"]
        let fields = fieldErrors.keys.sorted { lhs, rhs in
            let ranks = (leading.firstIndex(of: lhs.lowercased()) ?? leading.count, leading.firstIndex(of: rhs.lowercased()) ?? leading.count)
            return ranks.0 != ranks.1 ? ranks.0 < ranks.1 : lhs < rhs
        }
        return fields.lazy.compactMap { field in self.fieldErrors[field].flatMap { $0.isEmpty ? nil : $0.joined(separator: " ") } }.first
    }
}
