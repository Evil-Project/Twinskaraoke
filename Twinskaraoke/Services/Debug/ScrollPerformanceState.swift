import Combine
import SwiftUI

@MainActor
final class ScrollPerformanceState: ObservableObject {
    static let shared = ScrollPerformanceState()

    @Published private(set) var isScrolling = false

    private var activeScrollIDs = Set<UUID>()
    private var scrollEndTask: Task<Void, Never>?
    private var scrollEndGeneration: UInt = 0

    private init() {}

    func update(id: UUID, isScrolling scrolling: Bool) {
        if scrolling {
            cancelPendingScrollEnd()
            activeScrollIDs.insert(id)
        } else {
            activeScrollIDs.remove(id)
        }
        scheduleScrollStateUpdate()
    }

    private func scheduleScrollStateUpdate() {
        cancelPendingScrollEnd()
        if !activeScrollIDs.isEmpty {
            setScrolling(true)
            return
        }

        let generation = scrollEndGeneration
        scrollEndTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(140))
            } catch {
                return
            }
            guard let self, self.scrollEndGeneration == generation else { return }
            self.scrollEndTask = nil
            self.setScrolling(false)
        }
    }

    private func cancelPendingScrollEnd() {
        scrollEndGeneration &+= 1
        scrollEndTask?.cancel()
        scrollEndTask = nil
    }

    private func setScrolling(_ scrolling: Bool) {
        guard isScrolling != scrolling else { return }
        isScrolling = scrolling
    }
}
