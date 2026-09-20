import SwiftUI

private struct ZoomPushIsArrivingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var zoomPushIsArriving: Bool {
        get { self[ZoomPushIsArrivingKey.self] }
        set { self[ZoomPushIsArrivingKey.self] = newValue }
    }
}
