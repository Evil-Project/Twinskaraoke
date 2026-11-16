import Foundation

extension BandleMode {
    /// The modes players can pick. Extreme works end to end but isn't
    /// released on twinskaraoke.com yet, so it stays hidden until it is; add
    /// it back here to show it. With one mode, no picker is shown.
    static let visibleModes: [BandleMode] = [.normal]

    var title: String {
        switch self {
        case .normal: String(localized: "Normal")
        case .extreme: String(localized: "Extreme")
        }
    }
}
