import Foundation

enum LibrarySongSort: String, CaseIterable, Identifiable {
    case recentlyAdded
    case title
    case artist
    case duration

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .recentlyAdded: String(localized: "Recently Added")
        case .title: String(localized: "Title")
        case .artist: String(localized: "Artist")
        case .duration: String(localized: "Duration")
        }
    }

    var symbol: String {
        switch self {
        case .recentlyAdded: "clock"
        case .title: "textformat"
        case .artist: "person"
        case .duration: "timer"
        }
    }
}
