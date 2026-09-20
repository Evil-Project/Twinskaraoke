import Foundation
@MainActor
final class RefreshTracker {
    private var task: Task<Void, Never>?
    func track(_ task: Task<Void, Never>, cancellingPrevious: Bool = false) {
        if cancellingPrevious {
            self.task?.cancel()
        }
        self.task = task
    }
    func cancel() {
        task?.cancel()
        task = nil
    }
    func wait() async {
        guard let tracked = task else { return }
        await tracked.value
        if task == tracked {
            task = nil
        }
    }
}
