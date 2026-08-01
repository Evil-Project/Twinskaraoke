import Foundation

nonisolated struct WatchQueueEntry: Identifiable, Equatable, Sendable {
    let queueIndex: Int
    let song: Song

    var id: Int { queueIndex }
}
