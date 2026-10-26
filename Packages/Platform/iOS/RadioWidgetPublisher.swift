import Foundation
import WidgetKit

@MainActor
final class RadioWidgetPublisher {
    private var widgetPublishTask: Task<Void, Never>?

    func publish(_ metadata: RadioNowPlaying, fetchedAt: Date) {
        let snapshot = WidgetRadioSnapshot(metadata: metadata, fetchedAt: fetchedAt)
        let previousTask = widgetPublishTask
        widgetPublishTask = Task {
            await previousTask?.value
            let store = WidgetSnapshotStore()
            let previous = store.readRadio()
            let saved = await WidgetRadioRepository.cache(snapshot, store: store)
            // Still persist the successful fetch timestamp on unchanged polls.
            // Only visible metadata/artwork changes warrant a timeline reload.
            if !saved.hasSameContent(as: previous) {
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.radio)
            }
        }
    }
}
